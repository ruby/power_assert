# power_assert.rb
#
# Copyright (C) 2014 Kazuki Tsujimoto, All rights reserved.

begin
  TracePoint.new(:return, :c_return) {}
rescue
  raise LoadError, 'Fully compatible TracePoint API required'
end

require 'power_assert/version'

require 'ripper'

# NB: API is not fixed

module PowerAssert
  class Context
    Value = Struct.new(:name, :value, :column)
    Ident = Struct.new(:type, :name, :column)

    TARGET_CALLER_DIFF = {return: 5, c_return: 4}
    TARGET_CALLER_INDEX = {return: 3, c_return: 2}

    attr_reader :message_proc

    def initialize(assertion_proc, assertion_method)
      path = nil
      lineno = nil
      @line = nil
      methods = nil
      refs = nil
      method_ids = nil
      return_values = []
      @base_caller_length = -1
      @assertion_proc = assertion_proc
      @assertion_method_name = assertion_method.to_s
      @message_proc = -> {
        @assertion_message ||=
          @base_caller_length > 0 ? assertion_message(@line || '',
                                                      methods || [],
                                                      return_values,
                                                      refs || [],
                                                      assertion_proc.binding).freeze :
                                    nil
      }
      @proc_local_variables = assertion_proc.binding.eval('local_variables').map(&:to_s)
      @trace = TracePoint.new(:return, :c_return) do |tp|
        next if method_ids and ! method_ids.include?(tp.method_id)
        locs = tp.binding.eval('caller_locations')
        if locs.length - @base_caller_length == TARGET_CALLER_DIFF[tp.event]
          idx = TARGET_CALLER_INDEX[tp.event]
          unless path
            path = locs[idx].path
            lineno = locs[idx].lineno
            @line = open(path).each_line.drop(lineno - 1).first
            idents = extract_idents(Ripper.sexp(@line))
            methods, refs = idents.partition {|i| i.type == :method }
            method_ids = methods.map(&:name).map(&:to_sym).uniq
          end
          if path == locs[idx].path and lineno == locs[idx].lineno
            return_values << Value[tp.method_id.to_s, tp.return_value, nil]
          end
        end
      end
    end

    def yield
      do_yield(&@assertion_proc)
    end

    private

    def do_yield
      @trace.enable do
        @base_caller_length = caller_locations.length
        yield
      end
    end

    def assertion_message(line, methods, return_values, refs, proc_binding)
      set_column(line, methods, return_values)
      ref_values = refs.map {|i| Value[i.name, proc_binding.eval(i.name), i.column] }
      vals = (return_values + ref_values).find_all(&:column).sort_by(&:column).reverse
      if vals.empty?
        return line
      end
      fmt = (vals[0].column + 1).times.map {|i| vals.find {|v| v.column == i } ? "%<#{i}>s" : ' '  }.join
      ret = []
      ret << line.chomp
      ret << sprintf(fmt, vals.each_with_object({}) {|v, h| h[v.column.to_s.to_sym] = '|' }).chomp
      vals.each do |i|
        ret << sprintf(fmt,
                       vals.each_with_object({}) do |j, h|
                         h[j.column.to_s.to_sym] = [i.value.inspect, '|', ' '][i.column <=> j.column]
                       end).rstrip
      end
      ret.join("\n")
    end

    def set_column(line, methods, return_values)
      methods = methods.dup
      return_values.each do |val|
        idx = methods.index {|method| method.name == val.name }
        if idx
          val.column = methods.delete_at(idx).column
        end
      end
    end

    def extract_idents(sexp)
      tag, * = sexp
      case tag
      when :arg_paren, :assoc_splat, :fcall, :hash, :method_add_block, :string_literal
        extract_idents(sexp[1])
      when :assign, :massign
        extract_idents(sexp[2])
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
        [sexp[1], sexp[3]].flat_map {|s| extract_idents(s) }
      when :array
        sexp[1] ? sexp[1].flat_map {|s| extract_idents(s) } : []
      when :command_call
        [sexp[1], sexp[4], sexp[3]].flat_map {|s| extract_idents(s) }
      when :aref
        handle_columnless_ident(extract_idents(sexp[1]), :[], extract_idents(sexp[2]))
      when :method_add_arg
        idents = extract_idents(sexp[1])
        idents[0..-2] + extract_idents(sexp[2]) + [idents[-1]]
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
            tag3 == :@ident and mname == @assertion_method_name and (tag4 == :brace_block or tag4 == :do_block)
          ss.flat_map {|s| extract_idents(s) }
        else
          _, (s, *) = sexp
          extract_idents(s)
        end
      when :var_ref
        _, (tag, ref_name, (_, column)) = sexp
        case tag
        when :@kw
          if ref_name == 'self'
            [Ident[:ref, 'self', column]]
          else
            []
          end
        when :@const, :@cvar, :@ivar, :@gvar
          [Ident[:ref, ref_name, column]]
        else
          []
        end
      when :@ident, :@const
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
      :-@ => '-'
    }

    def handle_columnless_ident(left_idents, mid, right_idents)
      left_max = left_idents.max_by(&:column)
      right_min = right_idents.min_by(&:column)
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
      if left_idents.empty? and right_idents.empty?
        left_idents + right_idents
      elsif left_idents.empty?
        left_idents + right_idents + [Ident[:method, mname, indices.last]]
      else
        left_idents + right_idents + [Ident[:method, mname, indices.first]]
      end
    end
  end
  private_constant :Context

  def start(assertion_proc, assertion_method: nil)
    yield Context.new(assertion_proc, assertion_method)
  end
  module_function :start
end

if defined? RubyVM
  RubyVM::InstructionSequence.compile_option = {
    specialized_instruction: false
  }
end
