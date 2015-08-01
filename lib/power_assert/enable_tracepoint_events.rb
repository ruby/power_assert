if defined? RubyVM
  verbose = $VERBOSE
  begin
    $VERBOSE = nil
    module PowerAssert
      # set redefined flag
      basic_classes = [
        Fixnum, Float, String, Array, Hash, Bignum, Symbol, Time, Regexp
      ]

      basic_operators = [
        :+, :-, :*, :/, :%, :==, :===, :<, :<=, :<<, :[], :[]=,
        :length, :size, :empty?, :succ, :>, :>=, :!, :!=, :=~, :freeze
      ]

      basic_classes.each do |klass|
        basic_operators.each do |bop|
          refine(klass) do
            define_method(bop) {}
          end
        end
      end


      # bypass check_cfunc
      refine BasicObject do
        def !
        end

        def ==
        end
      end

      refine Module do
        def ==
        end
      end

      refine Symbol do
        def ==
        end
      end
    end
  ensure
    $VERBOSE = verbose
  end

  # disable optimization
  RubyVM::InstructionSequence.compile_option = {
    specialized_instruction: false
  }
end
