require_relative '../lib/cfhighlander.config.loader'

RSpec.describe Cfhighlander::Config::Loader, "#get_nested_config" do


  context "nested_config_files" do
    it "test single level" do
      loader = Cfhighlander::Config::Loader.new
      nested_config = loader.get_nested_config('a', { 'key' => 'value' })
      expected_component_config = {
          'components' => {
              'a' => {
                  'config' => { 'key' => 'value' }
              }
          }
      }
      expect(nested_config).to eq(expected_component_config)
    end
    it "test_config_4_levels_deep" do
      loader = Cfhighlander::Config::Loader.new
      nested_config = loader.get_nested_config('a.b.c.d', { 'key' => 'value' })
      expected_nested_config = {
          'components' => {
              'a' => {
                  'config' => {
                      'components' => {
                          'b' => {
                              'config' => {
                                  'components' => {
                                      'c' => {
                                          'config' => {
                                              'components' => {
                                                  'd' => {
                                                      'config' => {
                                                          'key' => 'value'
                                                      }
                                                  }
                                              }
                                          }
                                      }
                                  }
                              }
                          }
                      }
                  }
              }
          }
      }
      expect(nested_config).to eq(expected_nested_config)
    end
  end

end