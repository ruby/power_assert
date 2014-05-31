require 'power_assert/version'

require 'ripper'
require 'pattern-match'

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
      line = nil
      methods = nil
      refs = nil
      method_ids = nil
      return_values = []
      @base_caller_length = -1
      @assertion_proc = assertion_proc
      @message_proc = -> {
        @assertion_message ||=
          @base_caller_length > 0 ? assertion_message(line, methods, return_values, refs, @assertion_proc.binding).freeze : nil
      }
      @proc_local_variables = assertion_proc ? assertion_proc.binding.eval('local_variables').map(&:to_s) : []
      @trace = TracePoint.new(:return, :c_return) do |tp|
        next if method_ids and not method_ids.find {|i| i == tp.method_id }
        locs = tp.binding.eval('caller_locations')
        if locs.length - @base_caller_length == TARGET_CALLER_DIFF[tp.event]
          idx = TARGET_CALLER_INDEX[tp.event]
          path ||= locs[idx].path
          lineno ||= locs[idx].lineno
          line ||= open(path).each_line.drop(lineno - 1).first
          unless methods
            idents = extract_idents(Ripper.sexp(line), assertion_method)
            methods, refs = idents.partition {|i| i.type == :method }
          end
          method_ids = methods.map(&:name).map(&:to_sym)
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
      ref_values = refs ? refs.map {|i| Value[i.name, proc_binding.eval(i.name), i.column] } :[]
      vals = (return_values + ref_values).find_all(&:column).sort_by(&:column).reverse
      if vals.empty?
        return line || ''
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
      methods &&= methods.dup
      return_values.each do |val|
        idx = methods.index {|method| method.name == val.name }
        if idx and (m = methods.delete_at(idx)).column
          val.column = m.column
        else
          ridx = return_values.rindex {|i| i.name == val.name and i.column }
          method_name = val.name
          re = /
            #{'\b' if /\A\w/ =~ method_name}
            #{Regexp.escape(method_name)}
            #{'\b' if /\w\z/ =~ method_name}
          /x
          val.column = line.index(re, ridx ? return_values[ridx].column + 1 : 0)
        end
      end
    end

    def extract_idents(sexp, assertion_method = nil)
      match(sexp) do
        with(_[:program,
               _[_[:method_add_block,
                   _[:method_add_arg, _[:fcall, _[:@ident, assertion_method.to_s, _]], _],
                   _[Or(:brace_block, :do_block), _, ss]]]]) do
          ss.flat_map {|s| extract_idents(s) }
        end
        with(_[:program, _[s, *_]]) do
          extract_idents(s)
        end
        with(_[:method_add_arg, s0, s1]) do
          s0_methods = extract_idents(s0)
          s0_methods[0..-2] + extract_idents(s1) + [s0_methods[-1]]
        end
        with(_[:arg_paren, s]) do
          extract_idents(s)
        end
        with(_[:args_add_block, _[:args_add_star, ss0, *ss1], _]) do
          (ss0 + ss1).flat_map {|s| extract_idents(s) }
        end
        with(_[:args_add_block, ss, _]) do
          ss.flat_map {|s| extract_idents(s) }
        end
        with(_[:vcall, _[:@ident, name, _[_, column]]]) do
          [Ident[@proc_local_variables.include?(name) ? :ref : :method, name, column]]
        end
        with(_[:fcall, s]) do
          extract_idents(s)
        end
        with(_[:binary, *ss]) do
          ss.flat_map {|s| extract_idents(s) }
        end
        with(_[:call, s0, _, s1]) do
          [s0, s1].flat_map {|s| extract_idents(s) }
        end
        with(_[:method_add_block, s, _]) do
          extract_idents(s)
        end
        with(_[:hash, s]) do
          extract_idents(s)
        end
        with(_[:assoclist_from_args, ss]) do
          ss.flat_map {|s| extract_idents(s) }
        end
        with(_[:bare_assoc_hash, ss]) do
          ss.flat_map {|s| extract_idents(s) }
        end
        with(_[:assoc_new, *ss]) do
          ss.flat_map {|s| extract_idents(s) }
        end
        with(_[:assoc_splat, s]) do
          extract_idents(s)
        end
        with(_[:array, ss]) do
          ss.flat_map {|s| extract_idents(s) }
        end
        with(_[:command, *ss]) do
          ss.flat_map {|s| extract_idents(s) }
        end
        with(_[:assign, _, s]) do
          extract_idents(s)
        end
        with(_[:massign, _, s]) do
          extract_idents(s)
        end
        with(_[:paren, ss]) do
          ss.flat_map {|s| extract_idents(s) }
        end
        with(_[:var_ref, _[:@kw, "self", _[_, column]]]) do
          [Ident[:ref, "self", column]]
        end
        with(_[:var_ref, _[Or(:@const, :@cvar, :@ivar, :@gvar), ref_name, _[_, column]]]) do
          [Ident[:ref, ref_name, column]]
        end
        with(_[:@ident, method_name, _[_, column]]) do
          [Ident[:method, method_name, column]]
        end
        with(_[:@const, method_name, _[_, column]]) do
          [Ident[:method, method_name, column]]
        end
        with(s & Symbol) do
          [Ident[:method, s.to_s, nil]]
        end
        with(_) do
          []
        end
      end
    end
  end
  private_constant :Context

  def start(assertion_proc, assertion_method: nil)
    yield Context.new(assertion_proc, assertion_method)
  end
  module_function :start
end
