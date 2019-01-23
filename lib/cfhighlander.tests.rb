require 'yaml'
<<<<<<< HEAD
require 'json'
=======
>>>>>>> cftest command to run against test config on components

module CfHighlander
  class Tests

<<<<<<< HEAD
    attr_accessor :cases,
      :report,
      :exit_code,
      :report_path,
      :time,
      :timestamp

    def initialize(component_name,options)
      @component_name = component_name
      @tests_dir = options[:directory]
      @test_files = options[:tests] || Dir["#{@tests_dir}/*.test.yaml"]
      @report_path = "reports"
      @debug = false
      @cases = []
      @report = []
      @time = nil
      @timestamp = nil
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

    def print_results
      failures = @report.select { |k,v| k[:failure] }
      puts "\n\s\s============================"
      puts "\s\s#    CfHighlander Tests    #"
      puts "\s\s============================\n\n"
      puts "\s\sPass: #{cases.size - failures.size}"
      puts "\s\sFail: #{failures.size}"
      puts "\s\sTime: #{@time}\n\n"

      if failures.any?
        @exit_code = 1
        puts "\s\s=========Failures========="
        failures.each do |failure|
          puts "\s\sName: #{failure[:name]}"
          puts "\s\sTest: #{failure[:test]}"
          puts "\s\sType: #{failure[:type]}"
          puts "\s\sMessage: #{failure[:failure][:message]}"
=======
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
>>>>>>> cftest command to run against test config on components
          puts "\s\s-------------------------"
        end
      end
    end

<<<<<<< HEAD
    def report_dir
      FileUtils.mkdir_p(@report_path) unless Dir.exist?(@report_path)
    end

    def generate_report(type)
      report_dir
      failures = @report.select { |k,v| k[:message] }
      report = {}
      report[:component] = @component_name
      report[:tests] = cases.size.to_s
      report[:pass] = (cases.size - failures.size).to_s
      report[:failures] = failures.size.to_s
      report[:time] = @time.to_s
      report[:timestamp] = @timestamp.to_s
      report[:testcases] = @report
      case type
      when 'json'
        report_json(report)
      when 'xml'
        report_xml(report)
      end
    end

    def report_xml(report)
      testsuite = report.map { |k,v| "#{k}=\"#{v}\"" if k != :testcases }
      File.open("reports/report.xml","w") do |f|
        f.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
        f.write("<testsuite #{testsuite.join(' ')}>\n")
        report[:testcases].each do |test|
          testcase = test.map { |k,v| "#{k}=\"#{v}\"" if k != :failure }
          if test[:failure]
            f.write("\t<testcase #{testcase.join(' ')}>\n")
            f.write("\t\t<failure message=\"#{test[:failure][:message]}\" type=\"#{test[:failure][:type]}\"/>\n")
            f.write("\t</testcase>\n")
          else
            f.write("\t<testcase #{testcase.join(' ')}/>\n")
          end
        end
        f.write("</testsuite>")
      end
    end

    def report_json(report)
      File.open("reports/report.json","w") do |f|
        f.write(JSON.pretty_generate(report))
      end
    end

=======
>>>>>>> cftest command to run against test config on components
  end
end
