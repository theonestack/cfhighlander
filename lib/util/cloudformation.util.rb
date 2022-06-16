require_relative '../cfhighlander.model.component'
require_relative '../cfhighlander.error'
require_relative './debug.util'
require 'duplicate'

module Cfhighlander

  module Util

    class CloudFormation

      def self.flattenCloudformation(args = {})

        component = args.fetch(:component)
        template = component.highlander_dsl

        # make sure all mappings, resources and conditions
        # are named uniquely in all of the templates
        flatten_key_names(component, template)
        Debug.debug_dump_cfn(template, 'namespace_flat')

        # collect output values
        output_values = collect_output_values(template)
        Debug.debug_dump(output_values, 'outputs')

        # collect referenced parameters and convert to replacements
        component_replacements = collect_replacements(component, template, output_values)
        Debug.debug_dump(component_replacements, 'replacements')

        # apply replacements in referenced templates
        process_replacements(component, template, component_replacements)
        Debug.debug_dump_cfn(template, 'transformed')

        # inline all of the resources
        inline_resources(component, template)

        # remove substacks
        remove_inlined_component_stacks(component, template)

        # return inlined model
        return component.cfn_model_raw
      end

      def self.remove_inlined_component_stacks(component, template)
        model = component.cfn_model_raw
        template.subcomponents.each do |sub_component|
          next unless sub_component.inlined
          model['Resources'].delete(sub_component.cfn_name)
        end
      end

      def self.flatten_namespace(element_type, component, template)
        if component.cfn_model_raw.key? element_type
          keys_taken = component.cfn_model_raw[element_type].keys
        else
          keys_taken = []
        end
        template.subcomponents.each do |sub_component|
          next unless sub_component.inlined
          model = sub_component.component_loaded.cfn_model_raw
          model[element_type].keys.each do |key|
            if keys_taken.include? key
              candidate = "#{sub_component.component_loaded.name}#{key}"
              counter = 1
              while keys_taken.include? candidate
                candidate = "#{sub_component.component_loaded.name}#{key}#{counter}"
                counter = counter + 1
              end
              actual_key = candidate
              # we need to replace all as
              # resources can reference conditions
              # outputs can and will reference resources
              model[element_type][actual_key] = model[element_type][key]
              model[element_type].delete(key)
              case element_type
              when 'Resources'
                rename_resource(model, key, actual_key)
              when 'Mappings'
                rename_mapping(model, key, actual_key)
              when 'Conditions'
                rename_condition(model, key, actual_key)
              when 'Outputs'
                # outputs are not effecting anything within the same template
              end
              keys_taken << actual_key
            else
              keys_taken << key
            end
          end if model.key? element_type
        end
      end

      def self.inline_resources(component, template)
        inline_elements('Conditions', component, template)
        inline_elements('Mappings', component, template)
        inline_elements('Resources', component, template)

        # outputs are renamed AFTER all of the other processing
        # has been done, as outputs are referenced. Only
        # outputs of inlined components are renamed
        flatten_namespace('Outputs', component, template)
        Debug.debug_dump_cfn(template, 'flat.outputs')
        inline_elements('Outputs', component, template)
      end

      def self.inline_elements(element_name, component, template)
        parent_model = component.cfn_model_raw
        template.subcomponents.each do |sub_component|
          next unless sub_component.inlined
          model = sub_component.component_loaded.cfn_model_raw
          model[element_name].each do |resource, value|
            if sub_component.conditional
              # If the resource already has a conditon we need to combine it with the stack condition
              if element_name == 'Conditions'
                value = { "Fn::And" => [{"Condition" => sub_component.condition}, value]}
              end
              # Adds the condition to the inlined resource if it doesn't already have a condition
              if element_name == 'Resources'
                value['Condition'] = sub_component.condition unless value.has_key?('Condition')
              end
            end
            # effective extraction of child resource into parent
            # allows for line components to use - or _ in the component name
            # and still generate valid references
            safe_resource_name = resource.gsub('-','').gsub('_','')
            unless element_name == 'Outputs' && resource.end_with?('CfTemplateUrl')
              parent_model[element_name] = {} unless parent_model.key? element_name
              parent_model[element_name][safe_resource_name] = value
            end
          end if model.key? element_name
        end
      end

      def self.process_replacements(component, template, component_replacements)

        # replacement processing is done from least to most dependant component
        dependency_sorted_subcomponents = template.subcomponents.sort {|sc1, sc2|
          sc1_params = component.cfn_model_raw['Resources'][sc1.cfn_name]['Properties']['Parameters']
          sc2_params = component.cfn_model_raw['Resources'][sc2.cfn_name]['Properties']['Parameters']
          outval_refs_sc1 = find_outval_refs(sc1_params)
          outval_refs_sc2 = find_outval_refs(sc2_params)

          # if sc1 is dependant on sc2,
          # sc2 param outval refs should have sc1 output
          # and vice versa
          sc1_depends_sc2 = if outval_refs_sc1.find{|oref| oref[:component] == sc2.cfn_name}.nil? then false else true end
          sc2_depends_sc1 = if outval_refs_sc2.find{|oref| oref[:component] == sc1.cfn_name}.nil? then false else true end

          if (sc1_depends_sc2 and sc2_depends_sc1)
            raise StandardError, "Components #{sc1.cfn_name} and #{sc2.cfn_name} have circular dependency!!"
          end
          if sc1_depends_sc2 then
            +1
          elsif sc2_depends_sc1 then
            -1
          else
            0
          end
        }

        # process replacements in order from least dependant to
        # most dependant
        dependency_sorted_subcomponents.each_with_index do |sub_component, index|
          next unless sub_component.inlined
          component_name = sub_component.component_loaded.name
          if component_replacements.key? component_name
            if sub_component.component_loaded.cfn_model_raw.key? 'Outputs'
              outputs_apriori = duplicate(sub_component.component_loaded.cfn_model_raw['Outputs'])
            else
              outputs_apriori = {}
            end
            component_replacements[component_name].each do |replacement|
              node_replace(
                  sub_component.component_loaded.cfn_model_raw,
                  replacement[:search],
                  replacement[:replace]
              ) # some of the component outputs may be changed and thus replacements need be updated
            end
            iteration_index = 2
            outputs_apriori.each do |out_name, out_value|
              value_after_transform = sub_component.component_loaded.cfn_model_raw['Outputs'][out_name]
              # value of the output was changed by replacement
              unless out_value == value_after_transform
                # for all downstream dependant components
                propagated_update_index = index + 1
                while propagated_update_index < dependency_sorted_subcomponents.size
                  pc_name = dependency_sorted_subcomponents[propagated_update_index].component_loaded.name
                  component_replacements[pc_name].each do |replacement|
                    # replacements for dependant component needs to be updated as well
                    replace = replacement[:replace]

                    if out_value['Value'] == replace
                      replacement[:replace] = value_after_transform['Value']
                    else
                      node_replace(replacement[:replace], out_value['Value'], value_after_transform['Value'])
                    end

                  end if component_replacements.include? pc_name
                  propagated_update_index += 1
                end
                Debug.debug_dump(component_replacements, "replacements.#{iteration_index}")
                iteration_index += 1
              end
            end
          end
        end

        # process replacements on component itself
        component_replacements[component.name].each do |replacement|
          node_replace(component.cfn_model_raw, replacement[:search], replacement[:replace])
        end
      end

      def self.find_outval_refs(tree, outval_refs = [])
        tree.each do |key, val|

          # if we have located get att, it may be output value
          if key == 'Fn::GetAtt'
            if val.is_a? Array and val.size == 2
              if val[1].start_with? 'Outputs.'
                component = val[0]
                output = val[1].split('.')[1]
                outval_refs << { component: component, outputName: output }
              end
            end
          elsif val.is_a? Hash or val.is_a? Array
            # however we may also find output deeper in the tree
            # example being FnIf(condition, out1, out2)
            find_outval_refs(val, outval_refs)
          end

        end if tree.is_a? Hash

        tree.each do |element|
          find_outval_refs(element, outval_refs)
        end if tree.is_a? Array
        return outval_refs
      end

      def self.collect_replacements(component, template, output_values)
        replacements = {}

        # collect replacements for inlined components
        template.subcomponents.each do |sub_component|
          next unless sub_component.inlined
          component_loaded = sub_component.component_loaded
          replacements[component_loaded.name] = []
          sub_stack_def = component.cfn_model_raw['Resources'][sub_component.cfn_name]
          next unless sub_stack_def['Properties'].key? 'Parameters'
          params = sub_stack_def['Properties']['Parameters']
          params.each do |param_name, param_value|
            # if param value is hash, we may find output values
            # these should be replaced with inlined values
            if param_value.is_a? Hash
              outval_refs = find_outval_refs(param_value)
              outval_refs.each do |out_ref|
                # replacement only takes place if
                # source component is inlined as well
                # if source component is not inlined
                # it's output won't be collected
                source_sub_component = template.subcomponents.find {|sc| sc.component_loaded.name == out_ref[:component]}

                # if source component is not inlined we can replacement as-is
                next unless source_sub_component.inlined
                search = { 'Fn::GetAtt' => [
                    out_ref[:component],
                    "Outputs.#{out_ref[:outputName]}"
                ] }
                replacement = output_values[out_ref[:component]][out_ref[:outputName]]
                if param_value == search
                  param_value = replacement
                else
                  # parameter value may be deeper in the structure, e.g.
                  # member of Fn::If intrinsic function
                  node_replace(
                      param_value,
                      search,
                      replacement
                  )
                end if output_values.key? out_ref[:component]

              end
            end
            replacements[component_loaded.name] << {
                search: { 'Ref' => param_name },
                replace: param_value
            }
          end

        end

        # collect replacements to be performed on parameters of non-inlined components
        # that are referencing inlined components
        replacements[component.name] = []
        template.subcomponents.each do |sub_component|
          next if sub_component.inlined
          sub_stack_def = component.cfn_model_raw['Resources'][sub_component.cfn_name]
          next unless sub_stack_def['Properties'].key? 'Parameters'
          params = sub_stack_def['Properties']['Parameters']
          params.each do |param_name, param_value|
            if param_value.is_a? Hash
              outval_refs = find_outval_refs(param_value)

              # component is NOT inlined and has out references to components that MAY be inlined
              outval_refs.each do |out_ref|
                component_name = out_ref[:component]
                ref_sub_component = template.subcomponents.find {|sc| sc.name == component_name}

                if ref_sub_component.nil?
                  raise Cfhighlander::Error, "unable to find outputs from component #{component_name} reference by parameters in component #{sub_component.name}"
                end

                if ref_sub_component.inlined
                  # out refs here need to be replaced with actual values
                  replacement = output_values[out_ref[:component]][out_ref[:outputName]]
                  replacements[component.name] << {
                      search: { 'Fn::GetAtt' => [component_name, "Outputs.#{out_ref[:outputName]}"] },
                      replace: replacement
                  }
                end
              end
            end
          end
        end
        return replacements
      end

      def self.collect_output_values(template)
        output_vals = {}
        template.subcomponents.each do |sub_component|
          # we collect outputs only from inlined components
          model = sub_component.component_loaded.cfn_model_raw
          model['Outputs'].each do |name, value|
            output_vals[sub_component.component_loaded.name] = {} unless output_vals.key? sub_component.component_loaded.name
            output_vals[sub_component.component_loaded.name][name] = value['Value']
          end if model.key? 'Outputs'
        end
        return output_vals
      end

      ## if hash is treated as
      ## collection of tree structures
      ## where each key in Hash is root of the tree
      ## and value is subtree
      ## replace hash subtree with another subtree
      def self.node_replace(tree, search, replacement)
        if tree.is_a? Hash
          tree.each do |root, subtree|
            if subtree == search
              tree[root] = replacement
            elsif subtree.is_a? Hash or subtree.is_a? Array
              node_replace(subtree, search, replacement)
            end
          end
        elsif tree.is_a? Array
          tree.each do |element|
            if element == search
              tree[tree.index element] = replacement
            elsif element.is_a? Hash or element.is_a? Array
              node_replace(element, search, replacement)
            end
          end
        end
      end

      # rename cloudformation resource in model
      def self.rename_resource(tree, search, replacement)
        tree.keys.each do |k|
          v = tree[k]
          if k == 'Ref' and v == search
            tree[k] = replacement
          end

          if k == 'Fn::GetAtt' and v[0] == search
            tree[k] = [replacement, v[1]]
          end

          if v.is_a? Array or v.is_a? Hash
            rename_resource(v, search, replacement)
          end
        end if tree.is_a? Hash

        tree.each do |element|
          rename_resource(element, search, replacement)
        end if tree.is_a? Array

      end

      # rename cloudformation mapping in cfn model
      def self.rename_mapping(tree, search, replacement)
        tree.keys.each do |k|
          v = tree[k]
          if k == 'Fn::FindInMap' and v[0] == search
            tree[k] = [replacement, v[1], v[2]]
          end

          if v.is_a? Array or v.is_a? Hash
            rename_mapping(v, search, replacement)
          end
        end if tree.is_a? Hash

        tree.each do |element|
          rename_mapping(element, search, replacement)
        end if tree.is_a? Array

      end

      # rename cloudformation condition in cfn model
      def self.rename_condition(tree, search, replacement)
        # conditions can be referenced by Fn::If and Condition => cond
        tree.keys.each do |k|
          v = tree[k]
          if k == 'Fn::If' and v[0] == search
            tree[k] = [replacement, v[1], v[2]]
          end

          if k == 'Condition' and v == search
            tree[k] = replacement
          end

          if v.is_a? Array or v.is_a? Hash
            rename_condition(v, search, replacement)
          end
        end if tree.is_a? Hash

        tree.each do |element|
          rename_condition(element, search, replacement)
        end if tree.is_a? Array

      end

      ## Replace single value in tree structure (represented)
      # either as Hash or Array with another value
      def self.value_replace(tree, search, replacement)
        if tree.is_a? Hash
          tree.keys.each do |root|
            subtree = tree[root]
            if root == search
              tree[replacement] = subtree
              tree.delete(root)
            end
            if subtree == search
              tree[root] = replacement
            end
            if subtree.is_a? Hash or subtree.is_a? Array
              value_replace(subtree, search, replacement)
            end
          end
        elsif tree.is_a? Array
          tree.each do |element|
            if element == search
              tree[tree.index element] = replacement
            elsif element.is_a? Hash or element.is_a? Array
              value_replace(element, search, replacement)
            end
          end
        end
      end

      def self.flatten_key_names(component, template)
        flatten_namespace('Conditions', component, template)
        Debug.debug_dump_cfn(template, 'flat.conditions')

        flatten_namespace('Mappings', component, template)
        Debug.debug_dump_cfn(template, 'flat.mappings')

        flatten_namespace('Resources', component, template)
        Debug.debug_dump_cfn(template, 'flat.resources')
      end

    end
  end
end
