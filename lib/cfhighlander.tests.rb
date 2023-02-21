require 'yaml'
require 'json'
require 'util/hash.util'

module CfHighlander
  class Tests

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
        test_parameters = test_case['test_parameters'] || {}
        @cases << { 
          metadata: test_case['test_metadata'],
          test_parameters: test_parameters,
          file: file,
          config: load_default_config.deep_merge(test_case)
        }
      end
    end

    def load_default_config
      begin
        YAML.load_file("#{@component_name}.config.yaml", aliases: true) || {}
      rescue Errno::ENOENT => e
        {}
      end
    end

    def load_test_case(file)
      begin
        YAML.load_file(file, aliases: true)
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
          puts "\s\s-------------------------"
        end
      end
    end


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

  end
end
