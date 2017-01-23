require "bundler/gem_tasks"
require "rake/testtask"

task :default => :test
Rake::TestTask.new(:test) do |t|
  # helper(simplecov) must be required before loading power_assert
  t.ruby_opts = ["-w", "-r./test/test_helper"]
  t.test_files = FileList["test/**/*_test.rb"].exclude do |i|
    begin
      return false unless defined?(RubyVM)
      RubyVM::InstructionSequence.compile(open(i).read)
      false
    rescue SyntaxError
      true
    end
  end
end

desc "Run the benchmark suite"
task('benchmark') do
  Dir.glob('benchmarks/bm_*.rb').each do |f|
    load(f)
  end
end
