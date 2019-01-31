require 'yaml'

module CfHighlander
  class Tests

    attr_accessor :cases,
      :failures,
      :exit_code

    def initialize(component_name,options)
      @component_name = component_name
      @tests_dir = options[:directory]
      @test_files = options[:tests] || Dir["#{@tests_dir}/*.test.yaml"]
      @debug = false
      @cases = []
      @failures = []
      @exit_code = 0
    end

    def get_cases
      @test_files.each do |file|
        test_case = load_test_case(file)
        @cases << { metadata: test_case['test_metadata'], file: file, config: test_case }
      end
    end

    def load_test_case(file)
      begin
        YAML.load(File.read(file))
      rescue Errno::ENOENT => e
        abort "No test file found for #{file}"
      end
    end

    def failures(name,type,file,message)
      @failures << { name: name, type: type, file: file, message: message }
    end

    def print_results
      puts "\n\s\s============================"
      puts "\s\s#    CfHighlander Tests    #"
      puts "\s\s============================\n\n"
      puts "\s\sPass: #{@cases.size - @failures.size}"
      puts "\s\sFail: #{@failures.size}\n\n"

      if @failures.any?
        @exit_code = 1
        puts "\s\s======= FAILURES ========"
        @failures.each do |failure|
          puts "\s\sName: #{failure[:name]}"
          puts "\s\sTest: #{failure[:file]}"
          puts "\s\sType: #{failure[:type]}"
          puts "\s\sMessage: #{failure[:message]}"
          puts "\s\s-------------------------"
        end
      end
    end

  end
end
