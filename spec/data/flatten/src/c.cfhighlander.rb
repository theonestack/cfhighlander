CfhighlanderTemplate do

  Name 'c'

  Parameters do
    ComponentParam 'UseC1'
  end

  Condition('UseC1', FnEquals(Ref('UseC1'), 'true'))

  Component template: 'c1', name: 'c1a', render: Inline
  Component template: 'c1', name: 'c1b', render: Inline

  Component template:'c2',name:'c2', render: Inline do
    parameter name: 'c1OutParam', value: FnIf('UseC1',
        cfout('c1a.c1OutParam'),
        cfout('c1b.c1OutParam')
    )
  end


end