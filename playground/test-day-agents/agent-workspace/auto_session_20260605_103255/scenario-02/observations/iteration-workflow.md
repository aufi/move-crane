# Iteration Workflow Testing

## Question
Does it make sense to work stage-by-stage or regenerate all?

## Tests Performed
1. Created Stage 1 (KubernetesPlugin)
2. Created Stage 2 (EnvironmentCustomization)
3. Modified Stage 2
4. Re-ran Stage 2 only
5. Re-ran all stages
6. Tested --force flag

## Findings
- Stage re-run behavior: (see logs)
- --force flag behavior: (see logs)
- .work directory presence: yes

## Recommendations
(Based on test results)
