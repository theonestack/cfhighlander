require 'yaml'

module CfHighlander
  class Tests

    attr_reader :test_cases, :failures, :exit_code

    def initialize(component_name)
      @component_name = component_name
      @tests_file = "#{component_name}.tests.yaml"
      @test_cases = load_test_cases
      @failures = []
      @exit_code = 0
    end

    def load_test_cases
      tests = YAML.load(File.read(@tests_file))
      @test_cases = tests.map { |test,config| { name: test, config: config } }
    end

    def failures(name,type,message)
      @failures << { name: name, type: type, message: message }
    end

    def print_results
      puts "\n\s\s============================"
      puts "\s\s#    CfHighlander Tests    #"
      puts "\s\s============================\n\n"
      puts "\s\sPass: #{@test_cases.length - @failures.length}"
      puts "\s\sFail: #{@failures.length}\n\n"

      if @failures.any?
        @exit_code = 1
        puts "\s\s======= FAILURES ========"
        @failures.each do |failure|
          puts "\s\sTest: #{failure[:name]}"
          puts "\s\sType: #{failure[:type]}"
          puts "\s\sMessage: #{failure[:message]}"
          puts "\s\s-------------------------"
        end
      end
    end

  end
end
