module Cfhighlander

  module Dsl
    class DslBase

      attr_accessor :config

      # intrinsic functions

      def GetAtt(resource, property)
        return FnGetAtt(resource, property)
      end

      def FnGetAtt(resource, property)
        return {
            'Fn::GetAtt' => [resource, property]
        }
      end

      def FnImportValue(value)
        return {
            'Fn::ImportValue' => value
        }
      end

      def FnSub(string, replacementMap = nil)
        if replacementMap.nil?
          return { 'Fn::Sub' => string }
        else
          return { 'Fn::Sub' => [string, replacementMap] }
        end
      end

      def FnSplit(delimiter, source)
        return { 'Fn::Split' => [delimiter, source] }
      end

      def FnJoin(glue, pieces)
        return { 'Fn::Join' => [glue, pieces]}
      end

      def FnSelect(index, list)
        return { 'Fn::Select' => [index, list] }
      end

      def FnGetAZs(region = nil)
        if region.nil?
          region = AWSStackRegion()
        end
        return { 'Fn::GetAZs' => region }
      end

      def FnCidr(ip_block, count, sizeMask)
        return { 'Fn::Cidr' => [ip_block, count, sizeMask] }
      end

      def FnBase64(value)
        return { 'Fn::Base64' => value }
      end

      # pseudo reference
      def AWSStackRegion
        return Ref('AWS::Region')
      end

      def AWSStackName
        return Ref('AWS::StackName')
      end

      def AWSAccountId
        return Ref('AWS::AccountId')
      end

      def AWSURLSuffix
        return Ref('AWS::URLSuffix')
      end

      def AWSPartition
        return Ref('AWS::Partition')
      end

      def AWSNoValue
        return Ref('AWS::NoValue')
      end

      def AWSNotificationARNs
        return Ref('AWS::NotificationARNs')
      end

      # logic intrinsic functions
      def FnIf(condition, true_branch, false_branch)
        return { 'Fn::If' => [condition, true_branch, false_branch] }
      end

      def FnAnd(*args)
        return { 'Fn::And' => args }
      end

      def FnEquals(val1, val2)
        return { 'Fn::Equals' => [val1, val2] }
      end

      def FnNot(condition)
        return { 'Fn::Not' => [condition] }
      end

      def FnOr(*args)
        return { 'Fn::Or' => args }
      end


      def Ref(resource)
        return {
            'Ref' => resource
        }
      end

      def FnFindInMap(map, key, attr)
        return { 'Fn::FindInMap' => [map, key, attr] }
      end

      def FindInMap(map, key, attr)
        return FnFindInMap(map, key, attr)
      end

      def cfout(resource, output = nil)
        if output.nil?
          parts = resource.split('.')
          if parts.size() != 2
            raise "cfout('#{resource}'): If cfout given single argument cfout('component.OutputName') syntax must be used"
          else
            resource = parts[0]
            output = parts[1]
          end
        end

        return GetAtt(resource, "Outputs.#{output}")
      end


      def cfmap(map, key, attr)
        return FindInMap(map, key, attr)
      end


      def initialize (parent)
        @config = parent.config unless parent.nil?
      end

      def method_missing(method, *args)
        if @config.nil?
          raise StandardError, "#{self} no config!"
        end
        # return @config["#{method}"] unless @config["#{method}"].nil?
        raise StandardError, "#{self} Unknown method or variable #{method} in Cfhighlander template"
      end

    end

  end

end

