# power_assert.rb
#
# Copyright (C) 2014-2017 Kazuki Tsujimoto, All rights reserved.

begin
  captured = false
  TracePoint.new(:return, :c_return) do |tp|
    captured = true
    unless tp.binding and tp.return_value
      raise
    end
  end.enable { __id__ }
  raise unless captured
rescue
  raise LoadError, 'Fully compatible TracePoint API required'
end

require 'power_assert/version'
require 'power_assert/configuration'
require 'power_assert/enable_tracepoint_events'
require 'ripper'

module PowerAssert
  class << self
    def start(assertion_proc_or_source, assertion_method: nil, source_binding: TOPLEVEL_BINDING)
      if respond_to?(:clear_global_method_cache, true)
        clear_global_method_cache
      end
      yield BlockContext.new(assertion_proc_or_source, assertion_method, source_binding)
    end

    def trace(frame)
      begin
        raise 'Byebug is not started yet' unless Byebug.started?
      rescue NameError
        raise "PowerAssert.#{__method__} requires Byebug"
      end
      ctx = TraceContext.new(frame._binding)
      ctx.enable
      ctx
    end

    def app_caller_locations
      filter_locations(caller_locations)
    end

    private

    def filter_locations(locs)
      locs.drop_while {|i| ignored_file?(i.path) }.take_while {|i| ! ignored_file?(i.path) }
    end

    def ignored_file?(file)
      @ignored_libs ||= {PowerAssert => lib_dir(PowerAssert, :start, 1)}
      @ignored_libs[Byebug]    = lib_dir(Byebug, :load_settings, 2)      if defined?(Byebug) and ! @ignored_libs[Byebug]
      @ignored_libs[PryByebug] = lib_dir(Pry, :start_with_pry_byebug, 2) if defined?(PryByebug) and ! @ignored_libs[PryByebug]
      @ignored_libs.find do |_, dir|
        file.start_with?(dir)
      end
    end

    def lib_dir(obj, mid, depth)
      File.expand_path('../' * depth, obj.method(mid).source_location[0])
    end

    if defined?(RubyVM)
      def clear_global_method_cache
        eval('using PowerAssert.const_get(:Empty)', TOPLEVEL_BINDING)
      end
    end
  end

  module Empty
  end
  private_constant :Empty

  class InspectedValue
    def initialize(value)
      @value = value
    end

    def inspect
      @value
    end
  end
  private_constant :InspectedValue

  class SafeInspectable
    def initialize(value)
      @value = value
    end

    def inspect
      inspected = @value.inspect
      if Encoding.compatible?(Encoding.default_external, inspected)
        inspected
      else
        begin
          "#{inspected.encode(Encoding.default_external)}(#{inspected.encoding})"
        rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
          inspected.force_encoding(Encoding.default_external)
        end
      end
    rescue => e
      "InspectionFailure: #{e.class}: #{e.message.each_line.first}"
    end
  end
  private_constant :SafeInspectable

  class Formatter
    def initialize(value, indent)
      @value = value
      @indent = indent
    end

    def inspect
      if PowerAssert.configuration._colorize_message
        if PowerAssert.configuration._use_pp
          width = [Pry::Terminal.width! - 1 - @indent, 10].max
          Pry::ColorPrinter.pp(@value, '', width)
        else
          Pry::Code.new(@value.inspect).highlighted
        end
      else
        if PowerAssert.configuration._use_pp
          PP.pp(@value, '')
        else
          @value.inspect
        end
      end
    end
  end
  private_constant :Formatter

  class Context
    Value = Struct.new(:name, :value, :column)

    attr_reader :message_proc

    def initialize(base_caller_length)
      @fired = false
      @target_thread = Thread.current
      method_ids = nil
      return_values = []
      trace_alias_method = PowerAssert.configuration._trace_alias_method
      @trace = TracePoint.new(:return, :c_return) do |tp|
        method_ids ||= @parser.method_ids
        method_id = SUPPORT_ALIAS_METHOD                      ? tp.callee_id :
                    trace_alias_method && tp.event == :return ? tp.binding.eval('::Kernel.__callee__') :
                                                                tp.method_id
        next if ! method_ids[method_id]
        next if tp.event == :c_return and
                not (@parser.lineno == tp.lineno and @parser.path == tp.path)
        next unless tp.binding # workaround for ruby 2.2
        locs = PowerAssert.app_caller_locations
        diff = locs.length - base_caller_length
        if (tp.event == :c_return && diff == 1 || tp.event == :return && diff <= 2) and Thread.current == @target_thread
          idx = -(base_caller_length + 1)
          if @parser.path == locs[idx].path and @parser.lineno == locs[idx].lineno
            val = PowerAssert.configuration.lazy_inspection ?
              tp.return_value :
              InspectedValue.new(SafeInspectable.new(tp.return_value).inspect)
            return_values << Value[method_id.to_s, val, nil]
          end
        end
      end
      @message_proc = -> {
        raise RuntimeError, 'call #yield at first' unless fired?
        @message ||= build_assertion_message(@parser.line, @parser.idents, @parser.binding, return_values).freeze
      }
    end

    def message
      @message_proc.()
    end

    private

    def fired?
      @fired
    end

    def build_assertion_message(line, idents, proc_binding, return_values)
      if PowerAssert.configuration._colorize_message
        line = Pry::Code.new(line).highlighted
      end

      path = detect_path(idents, return_values)
      return line unless path

      delete_unidentified_calls(return_values, path)
      methods, refs = path.partition {|i| i.type == :method }
      return_values.zip(methods) do |i, j|
        unless i.name == j.name
          warn "power_assert: [BUG] Failed to get column: #{i.name}"
          return line
        end
        i.column = j.column
      end
      ref_values = refs.map {|i| Value[i.name, proc_binding.eval(i.name), i.column] }
      vals = (return_values + ref_values).find_all(&:column).sort_by(&:column).reverse
      return line if vals.empty?

      fmt = (0..vals[0].column).map {|i| vals.find {|v| v.column == i } ? "%<#{i}>s" : ' '  }.join
      lines = []
      lines << line.chomp
      lines << sprintf(fmt, vals.each_with_object({}) {|v, h| h[v.column.to_s.to_sym] = '|' }).chomp
      vals.each do |i|
        inspected_val = SafeInspectable.new(Formatter.new(i.value, i.column)).inspect
        inspected_val.each_line do |l|
          map_to = vals.each_with_object({}) do |j, h|
            h[j.column.to_s.to_sym] = [l, '|', ' '][i.column <=> j.column]
          end
          lines << encoding_safe_rstrip(sprintf(fmt, map_to))
        end
      end
      lines.join("\n")
    end

    def detect_path(idents, return_values)
      all_paths = @parser.call_paths
      return_value_names = return_values.map(&:name)
      uniq_calls = uniq_calls(all_paths)
      uniq_call = return_value_names.find {|i| uniq_calls.include?(i) }
      detected_paths = all_paths.find_all do |path|
        method_names = path.find_all {|ident| ident.type == :method }.map(&:name)
        break [path] if uniq_call and method_names.include?(uniq_call)
        return_value_names == method_names
      end
      return nil unless detected_paths.length == 1
      detected_paths[0]
    end

    def uniq_calls(paths)
      all_calls = enum_count_by(paths.map {|path| path.find_all {|ident| ident.type == :method }.map(&:name).uniq }.flatten) {|i| i }
      all_calls.find_all {|_, call_count| call_count == 1 }.map {|name, _| name }
    end

    def delete_unidentified_calls(return_values, path)
      return_value_num_of_calls = enum_count_by(return_values, &:name)
      path_num_of_calls = enum_count_by(path.find_all {|ident| ident.type == :method }, &:name)
      identified_calls = return_value_num_of_calls.find_all {|name, num| path_num_of_calls[name] == num }.map(&:first)
      return_values.delete_if {|val| ! identified_calls.include?(val.name) }
      path.delete_if {|ident| ident.type == :method and ! identified_calls.include?(ident.name) }
    end

    def enum_count_by(enum, &blk)
      Hash[enum.group_by(&blk).map{|k, v| [k, v.length] }]
    end

    def encoding_safe_rstrip(str)
      str.rstrip
    rescue ArgumentError, Encoding::CompatibilityError
      enc = str.encoding
      if enc.ascii_compatible?
        str.b.rstrip.force_encoding(enc)
      else
        str
      end
    end
  end
  private_constant :Context

  class BlockContext < Context
    def initialize(assertion_proc_or_source, assertion_method, source_binding)
      super(0)
      if assertion_proc_or_source.respond_to?(:to_proc)
        @assertion_proc = assertion_proc_or_source.to_proc
        line = nil
      else
        @assertion_proc = source_binding.eval "Proc.new {#{assertion_proc_or_source}}"
        line = assertion_proc_or_source
      end
      @parser = Parser::DUMMY
      @trace_call = TracePoint.new(:call, :c_call) do |tp|
        if Thread.current == @target_thread
          @trace_call.disable
          locs = PowerAssert.app_caller_locations
          path = locs.last.path
          lineno = locs.last.lineno
          line ||= open(path).each_line.drop(lineno - 1).first
          @parser = Parser.new(line, path, lineno, @assertion_proc.binding, assertion_method.to_s)
        end
      end
    end

    def yield
      @fired = true
      do_yield(&@assertion_proc)
    end

    private

    def do_yield
      @trace.enable do
        @trace_call.enable do
          yield
        end
      end
    end
  end
  private_constant :BlockContext

  class TraceContext < Context
    def initialize(binding)
      target_frame, *base = PowerAssert.app_caller_locations
      super(base.length)
      path = target_frame.path
      lineno = target_frame.lineno
      line = open(path).each_line.drop(lineno - 1).first
      @parser = Parser.new(line, path, lineno, binding)
    end

    def enable
      @fired = true
      @trace.enable
    end

    def disable
      @trace.disable
    end

    def enabled?
      @trace.enabled?
    end
  end
  private_constant :TraceContext

  class Parser
    Ident = Struct.new(:type, :name, :column)

    attr_reader :line, :path, :lineno, :binding

    def initialize(line, path, lineno, binding, assertion_method_name = nil)
      @line = line
      @path = path
      @lineno = lineno
      @binding = binding
      @proc_local_variables = binding.eval('local_variables').map(&:to_s)
      @assertion_method_name = assertion_method_name
    end

    def idents
      @idents ||= extract_idents(Ripper.sexp(@line))
    end

    def call_paths
      collect_paths(idents).uniq
    end

    def method_ids
      methods = idents.flatten.find_all {|i| i.type == :method }
      methods.map(&:name).map(&:to_sym).each_with_object({}) {|i, h| h[i] = true }
    end

    private

    class Branch < Array
    end

    #
    # Returns idents as graph structure.
    #
    #                                                  +--c--b--+
    #  extract_idents(Ripper.sexp('a&.b(c).d')) #=> a--+        +--d
    #                                                  +--------+
    #
    def extract_idents(sexp)
      tag, * = sexp
      case tag
      when :arg_paren, :assoc_splat, :fcall, :hash, :method_add_block, :string_literal
        extract_idents(sexp[1])
      when :assign, :massign
        extract_idents(sexp[2])
      when :opassign
        _, _, (_, op_name, (_, op_column)), s0 = sexp
        extract_idents(s0) + [Ident[:method, op_name.sub(/=\z/, ''), op_column]]
      when :assoclist_from_args, :bare_assoc_hash, :dyna_symbol, :paren, :string_embexpr,
        :regexp_literal, :xstring_literal
        sexp[1].flat_map {|s| extract_idents(s) }
      when :assoc_new, :command, :dot2, :dot3, :string_content
        sexp[1..-1].flat_map {|s| extract_idents(s) }
      when :unary
        handle_columnless_ident([], sexp[1], extract_idents(sexp[2]))
      when :binary
        handle_columnless_ident(extract_idents(sexp[1]), sexp[2], extract_idents(sexp[3]))
      when :call
        with_safe_op = sexp[2] == :"&."
        if sexp[3] == :call
          handle_columnless_ident(extract_idents(sexp[1]), :call, [], with_safe_op)
        else
          extract_idents(sexp[1]) + (with_safe_op ? [Branch[extract_idents(sexp[3]), []]] : extract_idents(sexp[3]))
        end
      when :array
        sexp[1] ? sexp[1].flat_map {|s| extract_idents(s) } : []
      when :command_call
        [sexp[1], sexp[4], sexp[3]].flat_map {|s| extract_idents(s) }
      when :aref
        handle_columnless_ident(extract_idents(sexp[1]), :[], extract_idents(sexp[2]))
      when :method_add_arg
        idents = extract_idents(sexp[1])
        if idents.empty?
          # idents may be empty(e.g. ->{}.())
          extract_idents(sexp[2])
        else
          if idents[-1].kind_of?(Branch) and idents[-1][1].empty?
            # Safe navigation operator is used. See :call clause also.
            idents[0..-2] + [Branch[extract_idents(sexp[2]) + idents[-1][0], []]]
          else
            idents[0..-2] + extract_idents(sexp[2]) + [idents[-1]]
          end
        end
      when :args_add_block
        _, (tag, ss0, *ss1), _ = sexp
        if tag == :args_add_star
          (ss0 + ss1).flat_map {|s| extract_idents(s) }
        else
          sexp[1].flat_map {|s| extract_idents(s) }
        end
      when :vcall
        _, (tag, name, (_, column)) = sexp
        if tag == :@ident
          [Ident[@proc_local_variables.include?(name) ? :ref : :method, name, column]]
        else
          []
        end
      when :program
        _, ((tag0, (tag1, (tag2, (tag3, mname, _)), _), (tag4, _, ss))) = sexp
        if tag0 == :method_add_block and tag1 == :method_add_arg and tag2 == :fcall and
            (tag3 == :@ident or tag3 == :@const) and mname == @assertion_method_name and (tag4 == :brace_block or tag4 == :do_block)
          ss.flat_map {|s| extract_idents(s) }
        else
          _, (s, *) = sexp
          extract_idents(s)
        end
      when :ifop
        _, s0, s1, s2 = sexp
        [*extract_idents(s0), Branch[extract_idents(s1), extract_idents(s2)]]
      when :if_mod, :unless_mod
        _, s0, s1 = sexp
        [*extract_idents(s0), Branch[extract_idents(s1), []]]
      when :var_ref, :var_field
        _, (tag, ref_name, (_, column)) = sexp
        case tag
        when :@kw
          if ref_name == 'self'
            [Ident[:ref, 'self', column]]
          else
            []
          end
        when :@ident, :@const, :@cvar, :@ivar, :@gvar
          [Ident[:ref, ref_name, column]]
        else
          []
        end
      when :@ident, :@const, :@op
        _, method_name, (_, column) = sexp
        [Ident[:method, method_name, column]]
      else
        []
      end
    end

    def str_indices(str, re, offset, limit)
      idx = str.index(re, offset)
      if idx and idx <= limit
        [idx, *str_indices(str, re, idx + 1, limit)]
      else
        []
      end
    end

    MID2SRCTXT = {
      :[] => '[',
      :+@ => '+',
      :-@ => '-',
      :call => '('
    }

    def handle_columnless_ident(left_idents, mid, right_idents, with_safe_op = false)
      left_max = left_idents.flatten.max_by(&:column)
      right_min = right_idents.flatten.min_by(&:column)
      bg = left_max ? left_max.column + left_max.name.length : 0
      ed = right_min ? right_min.column - 1 : @line.length - 1
      mname = mid.to_s
      srctxt = MID2SRCTXT[mid] || mname
      re = /
        #{'\b' if /\A\w/ =~ srctxt}
        #{Regexp.escape(srctxt)}
        #{'\b' if /\w\z/ =~ srctxt}
      /x
      indices = str_indices(@line, re, bg, ed)
      if indices.length == 1 or !(right_idents.empty? and left_idents.empty?)
        ident = Ident[:method, mname, right_idents.empty? ? indices.first : indices.last]
        left_idents + right_idents + (with_safe_op ? [Branch[[ident], []]] : [ident])
      else
        left_idents + right_idents
      end
    end

    def collect_paths(idents, prefixes = [[]], index = 0)
      if index < idents.length
        node = idents[index]
        if node.kind_of?(Branch)
          prefixes = node.flat_map {|n| collect_paths(n, prefixes, 0) }
        else
          prefixes = prefixes.empty? ? [[node]] : prefixes.map {|prefix| prefix + [node] }
        end
        collect_paths(idents, prefixes, index + 1)
      else
        prefixes
      end
    end

    class DummyParser < Parser
      def initialize
        super('', nil, nil, TOPLEVEL_BINDING)
      end

      def idents
        []
      end

      def call_paths
        []
      end
    end
    DUMMY = DummyParser.new
  end
  private_constant :Parser
end
