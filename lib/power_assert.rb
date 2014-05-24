require 'power_assert/version'

require 'ripper'
require 'pattern-match'

# NB: API is not fixed

module PowerAssert
  class Context
    RetValue = Struct.new(:method_id, :value, :column)

    TARGET_CALLER_DIFF = {return: 5, c_return: 4}
    TARGET_CALLER_INDEX = {return: 3, c_return: 2}

    attr_reader :message_proc

    def initialize
      path = nil
      lineno = nil
      line = nil
      methods = nil
      method_ids = nil
      values = []
      @base_caller_length = -1
      @message_proc = -> {
        @assertion_message ||= @base_caller_length > 0 ? assertion_message(line, methods, values).freeze : nil
      }
      @trace = TracePoint.new(:return, :c_return) do |tp|
        next if method_ids and not method_ids.find {|i| i == tp.method_id }
        locs = tp.binding.eval('caller_locations')
        if locs.length - @base_caller_length == TARGET_CALLER_DIFF[tp.event]
          idx = TARGET_CALLER_INDEX[tp.event]
          path ||= locs[idx].path
          lineno ||= locs[idx].lineno
          line ||= open(path).each_line.drop(lineno - 1).first
          methods ||= extract_methods(Ripper.sexp(line))
          method_ids ||= methods.map(&:first).map(&:to_sym)
          if path == locs[idx].path and lineno == locs[idx].lineno
            values << RetValue[tp.method_id, tp.return_value, nil]
          end
        end
      end
    end

    def yield
      @trace.enable do
        @base_caller_length = caller_locations.length
        yield
      end
    end

    private

    def assertion_message(line, methods, values)
      set_column(line, methods, values)
      vals = values.find_all(&:column).sort_by(&:column).reverse
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

    def set_column(line, methods, values)
      values.each do |val|
        idx = methods.index {|(method_name,*)| method_name == val.method_id.to_s }
        if idx
          m = methods.delete_at(idx)
          val.column = m[1][1]
        else
          ridx = values.rindex {|i| i.method_id == val.method_id and i.column }
          val.column = line.index(/\b#{Regexp.escape(val.method_id.to_s)}\b/, ridx ? values[ridx].column + 1 : 0)
        end
      end
    end

    def extract_methods(sexp)
      match(sexp) do
        with(_[:program, _[s, *_], *_]) do
          extract_methods(s)
        end
        with(_[:method_add_arg, s0, s1]) do
          s0_methods = extract_methods(s0)
          s0_methods[0..-2] + extract_methods(s1) + [s0_methods[-1]]
        end
        with(_[:arg_paren, s]) do
          extract_methods(s)
        end
        with(_[:args_add_block, _[s], _]) do
          extract_methods(s)
        end
        with(_[:vcall, s]) do
          extract_methods(s)
        end
        with(_[:fcall, s]) do
          extract_methods(s)
        end
        with(_[:@ident, method_name, pos]) do
          [[method_name, pos]]
        end
        with(_[:binary, *ss]) do
          ss.flat_map {|i| extract_methods(i) }
        end
        with(_[:call, *ss]) do
          ss.flat_map {|i| extract_methods(i) }
        end
        with(_[:method_add_block, s, _]) do
          extract_methods(s)
        end
        with(s & Symbol & Not(:".")) do
          [[s.to_s, [nil, nil]]]
        end
        with(_[:hash, s]) do
          extract_methods(s)
        end
        with(_[:assoclist_from_args, s]) do
          extract_methods(s)
        end
        with(_[:bare_assoc_hash, s]) do
          extract_methods(s)
        end
        with(_[_[:assoc_new, sss, ___], ___]) do
          sss.flat_map {|ss| ss.flat_map {|s| extract_methods(s) } }
        end
        with(_[:array, _[*ss]]) do
          ss.flat_map {|i| extract_methods(i) }
        end
        with(_) do
          []
        end
      end
    end
  end

  def start
    yield Context.new
  end
  module_function :start
end
