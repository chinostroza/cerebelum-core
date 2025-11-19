defmodule Cerebelum.Application.UseCases.ValidateBlueprintTest do
  use ExUnit.Case, async: true

  alias Cerebelum.Application.UseCases.ValidateBlueprint

  describe "execute/1 - valid blueprints" do
    test "accepts valid blueprint with timeline only" do
      blueprint = %{
        workflow_module: "MyApp.TestWorkflow",
        language: "kotlin",
        definition: %{
          timeline: [
            %{name: "step1", depends_on: []},
            %{name: "step2", depends_on: ["step1"]},
            %{name: "step3", depends_on: ["step2"]}
          ],
          diverge_rules: [],
          branch_rules: [],
          inputs: %{}
        }
      }

      assert {:ok, result} = ValidateBlueprint.execute(blueprint)
      assert result.errors == []
      assert is_binary(result.workflow_hash)
      assert String.length(result.workflow_hash) == 64  # SHA256 hex
    end

    test "accepts valid blueprint with diverge rules" do
      blueprint = %{
        workflow_module: "MyApp.WorkflowWithDiverge",
        language: "typescript",
        definition: %{
          timeline: [
            %{name: "step1", depends_on: []},
            %{name: "step2", depends_on: []},
            %{name: "step3", depends_on: []}
          ],
          diverge_rules: [
            %{
              from_step: "step1",
              patterns: [
                %{pattern: ":ok", target: "step2"},
                %{pattern: ":error", target: "step3"}
              ]
            }
          ],
          branch_rules: [],
          inputs: %{}
        }
      }

      assert {:ok, result} = ValidateBlueprint.execute(blueprint)
      assert result.errors == []
    end

    test "accepts valid blueprint with branch rules" do
      blueprint = %{
        workflow_module: "MyApp.WorkflowWithBranch",
        language: "python",
        definition: %{
          timeline: [
            %{name: "step1", depends_on: []},
            %{name: "step2", depends_on: []},
            %{name: "step3", depends_on: []}
          ],
          diverge_rules: [],
          branch_rules: [
            %{
              from_step: "step1",
              branches: [
                %{
                  condition: "result > 10",
                  action: %{type: "skip_to", target_step: "step3"}
                }
              ]
            }
          ],
          inputs: %{}
        }
      }

      assert {:ok, result} = ValidateBlueprint.execute(blueprint)
      assert result.errors == []
    end

    test "generates same hash for identical blueprints" do
      blueprint1 = %{
        workflow_module: "MyApp.Workflow",
        language: "kotlin",
        definition: %{
          timeline: [%{name: "step1", depends_on: []}],
          diverge_rules: [],
          branch_rules: [],
          inputs: %{}
        }
      }

      blueprint2 = %{
        workflow_module: "MyApp.Workflow",
        language: "kotlin",
        definition: %{
          timeline: [%{name: "step1", depends_on: []}],
          diverge_rules: [],
          branch_rules: [],
          inputs: %{}
        }
      }

      {:ok, result1} = ValidateBlueprint.execute(blueprint1)
      {:ok, result2} = ValidateBlueprint.execute(blueprint2)

      assert result1.workflow_hash == result2.workflow_hash
    end

    test "generates different hash for different blueprints" do
      blueprint1 = %{
        workflow_module: "MyApp.Workflow",
        language: "kotlin",
        definition: %{
          timeline: [%{name: "step1", depends_on: []}],
          diverge_rules: [],
          branch_rules: [],
          inputs: %{}
        }
      }

      blueprint2 = %{
        workflow_module: "MyApp.Workflow",
        language: "kotlin",
        definition: %{
          timeline: [%{name: "step1", depends_on: []}, %{name: "step2", depends_on: []}],
          diverge_rules: [],
          branch_rules: [],
          inputs: %{}
        }
      }

      {:ok, result1} = ValidateBlueprint.execute(blueprint1)
      {:ok, result2} = ValidateBlueprint.execute(blueprint2)

      assert result1.workflow_hash != result2.workflow_hash
    end
  end

  describe "execute/1 - structure validation" do
    test "rejects blueprint missing workflow_module" do
      blueprint = %{
        language: "kotlin",
        definition: %{
          timeline: [%{name: "step1", depends_on: []}],
          diverge_rules: [],
          branch_rules: [],
          inputs: %{}
        }
      }

      assert {:error, result} = ValidateBlueprint.execute(blueprint)
      assert "Missing required field: workflow_module" in result.errors
    end

    test "rejects blueprint missing language" do
      blueprint = %{
        workflow_module: "MyApp.Workflow",
        definition: %{
          timeline: [%{name: "step1", depends_on: []}],
          diverge_rules: [],
          branch_rules: [],
          inputs: %{}
        }
      }

      assert {:error, result} = ValidateBlueprint.execute(blueprint)
      assert "Missing required field: language" in result.errors
    end

    test "rejects blueprint missing definition" do
      blueprint = %{
        workflow_module: "MyApp.Workflow",
        language: "kotlin"
      }

      assert {:error, result} = ValidateBlueprint.execute(blueprint)
      assert "Missing required field: definition" in result.errors
    end

    test "rejects blueprint with empty timeline" do
      blueprint = %{
        workflow_module: "MyApp.Workflow",
        language: "kotlin",
        definition: %{
          timeline: [],
          diverge_rules: [],
          branch_rules: [],
          inputs: %{}
        }
      }

      assert {:error, result} = ValidateBlueprint.execute(blueprint)
      assert "Timeline cannot be empty" in result.errors
    end

    test "rejects step without name" do
      blueprint = %{
        workflow_module: "MyApp.Workflow",
        language: "kotlin",
        definition: %{
          timeline: [
            %{depends_on: []},  # Missing name
            %{name: "step2", depends_on: []}
          ],
          diverge_rules: [],
          branch_rules: [],
          inputs: %{}
        }
      }

      assert {:error, result} = ValidateBlueprint.execute(blueprint)
      assert Enum.any?(result.errors, &String.contains?(&1, "missing name"))
    end
  end

  describe "execute/1 - reference validation" do
    test "rejects undefined step in depends_on" do
      blueprint = %{
        workflow_module: "MyApp.Workflow",
        language: "kotlin",
        definition: %{
          timeline: [
            %{name: "step1", depends_on: ["nonexistent"]}
          ],
          diverge_rules: [],
          branch_rules: [],
          inputs: %{}
        }
      }

      assert {:error, result} = ValidateBlueprint.execute(blueprint)
      assert Enum.any?(result.errors, &String.contains?(&1, "depends on undefined step 'nonexistent'"))
    end

    test "rejects undefined step in diverge rule" do
      blueprint = %{
        workflow_module: "MyApp.Workflow",
        language: "kotlin",
        definition: %{
          timeline: [
            %{name: "step1", depends_on: []}
          ],
          diverge_rules: [
            %{
              from_step: "nonexistent",
              patterns: [%{pattern: ":ok", target: "step1"}]
            }
          ],
          branch_rules: [],
          inputs: %{}
        }
      }

      assert {:error, result} = ValidateBlueprint.execute(blueprint)
      assert Enum.any?(result.errors, &String.contains?(&1, "Diverge rule references undefined step 'nonexistent'"))
    end

    test "rejects undefined target in diverge pattern" do
      blueprint = %{
        workflow_module: "MyApp.Workflow",
        language: "kotlin",
        definition: %{
          timeline: [
            %{name: "step1", depends_on: []}
          ],
          diverge_rules: [
            %{
              from_step: "step1",
              patterns: [%{pattern: ":ok", target: "nonexistent"}]
            }
          ],
          branch_rules: [],
          inputs: %{}
        }
      }

      assert {:error, result} = ValidateBlueprint.execute(blueprint)
      assert Enum.any?(result.errors, &String.contains?(&1, "Diverge pattern references undefined step 'nonexistent'"))
    end

    test "rejects undefined step in branch rule" do
      blueprint = %{
        workflow_module: "MyApp.Workflow",
        language: "kotlin",
        definition: %{
          timeline: [
            %{name: "step1", depends_on: []}
          ],
          diverge_rules: [],
          branch_rules: [
            %{
              from_step: "nonexistent",
              branches: [
                %{condition: "true", action: %{type: "skip_to", target_step: "step1"}}
              ]
            }
          ],
          inputs: %{}
        }
      }

      assert {:error, result} = ValidateBlueprint.execute(blueprint)
      assert Enum.any?(result.errors, &String.contains?(&1, "Branch rule references undefined step 'nonexistent'"))
    end

    test "rejects undefined target in branch action" do
      blueprint = %{
        workflow_module: "MyApp.Workflow",
        language: "kotlin",
        definition: %{
          timeline: [
            %{name: "step1", depends_on: []}
          ],
          diverge_rules: [],
          branch_rules: [
            %{
              from_step: "step1",
              branches: [
                %{condition: "true", action: %{type: "skip_to", target_step: "nonexistent"}}
              ]
            }
          ],
          inputs: %{}
        }
      }

      assert {:error, result} = ValidateBlueprint.execute(blueprint)
      assert Enum.any?(result.errors, &String.contains?(&1, "Branch action references undefined step 'nonexistent'"))
    end
  end

  describe "execute/1 - cycle detection" do
    test "rejects simple back_to cycle" do
      blueprint = %{
        workflow_module: "MyApp.Workflow",
        language: "kotlin",
        definition: %{
          timeline: [
            %{name: "step1", depends_on: []},
            %{name: "step2", depends_on: []}
          ],
          diverge_rules: [],
          branch_rules: [
            %{
              from_step: "step1",
              branches: [
                %{condition: "true", action: %{type: "back_to", target_step: "step1"}}
              ]
            }
          ],
          inputs: %{}
        }
      }

      assert {:error, result} = ValidateBlueprint.execute(blueprint)
      assert Enum.any?(result.errors, &String.contains?(&1, "Cycle detected in back_to chain"))
    end

    test "rejects indirect back_to cycle" do
      blueprint = %{
        workflow_module: "MyApp.Workflow",
        language: "kotlin",
        definition: %{
          timeline: [
            %{name: "step1", depends_on: []},
            %{name: "step2", depends_on: []},
            %{name: "step3", depends_on: []}
          ],
          diverge_rules: [],
          branch_rules: [
            %{
              from_step: "step1",
              branches: [
                %{condition: "true", action: %{type: "back_to", target_step: "step2"}}
              ]
            },
            %{
              from_step: "step2",
              branches: [
                %{condition: "true", action: %{type: "back_to", target_step: "step1"}}
              ]
            }
          ],
          inputs: %{}
        }
      }

      assert {:error, result} = ValidateBlueprint.execute(blueprint)
      assert Enum.any?(result.errors, &String.contains?(&1, "Cycle detected in back_to chain"))
    end

    test "accepts valid back_to without cycle" do
      blueprint = %{
        workflow_module: "MyApp.Workflow",
        language: "kotlin",
        definition: %{
          timeline: [
            %{name: "step1", depends_on: []},
            %{name: "step2", depends_on: []},
            %{name: "step3", depends_on: []}
          ],
          diverge_rules: [],
          branch_rules: [
            %{
              from_step: "step3",
              branches: [
                %{condition: "retry", action: %{type: "back_to", target_step: "step1"}}
              ]
            }
          ],
          inputs: %{}
        }
      }

      assert {:ok, result} = ValidateBlueprint.execute(blueprint)
      assert result.errors == []
    end
  end

  describe "execute/1 - multiple errors" do
    test "returns all validation errors" do
      blueprint = %{
        workflow_module: "MyApp.Workflow",
        language: "kotlin",
        definition: %{
          timeline: [
            %{name: "step1", depends_on: ["nonexistent1"]},
            %{name: "step2", depends_on: ["nonexistent2"]}
          ],
          diverge_rules: [],
          branch_rules: [],
          inputs: %{}
        }
      }

      assert {:error, result} = ValidateBlueprint.execute(blueprint)
      assert length(result.errors) >= 2
    end
  end
end
