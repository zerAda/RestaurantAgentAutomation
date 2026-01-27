#!/usr/bin/env python3
"""
Patch Workflows - Fix known bugs in n8n workflow JSON files
"""
import json
import os
import re
from pathlib import Path

WORKFLOWS_DIR = Path(__file__).parent.parent / "workflows"

def fix_js_deny_reason_bug(js_code):
    """
    Fix the bug where denyReason is used before declaration.

    Bug pattern:
        if (denyReason !== '') { authOk = false; }
        ...
        let denyReason = authOk ? ...

    Fix: Remove the premature if statement (it's redundant anyway)
    """
    # Pattern to find the buggy if statement
    buggy_pattern = r"if\s*\(\s*denyReason\s*!==\s*['\"]+'['\"]*\s*\)\s*\{\s*\n?\s*//.*\n?\s*authOk\s*=\s*false;\s*\}"

    # Remove the buggy if statement entirely (it's checking denyReason before it's set)
    fixed_code = re.sub(buggy_pattern, "// denyReason check moved after declaration", js_code)

    return fixed_code

def add_postgres_credentials(node):
    """
    Add default PostgreSQL credentials reference to nodes that need it.
    """
    if node.get("type") == "n8n-nodes-base.postgres" and "credentials" not in node:
        node["credentials"] = {
            "postgres": {
                "id": "postgres-resto-bot",
                "name": "PostgreSQL Resto Bot"
            }
        }
    return node

def fix_execute_workflow_syntax(node):
    """
    Fix Execute Workflow nodes with incorrect expression syntax.
    {{$env.VAR}} should be ={{$env.VAR}}
    """
    if node.get("type") == "n8n-nodes-base.executeWorkflow":
        params = node.get("parameters", {})
        workflow_id = params.get("workflowId", "")
        if isinstance(workflow_id, str):
            # Fix {{$env...}} to ={{$env...}}
            if workflow_id.startswith("={{") and "{{" in workflow_id:
                fixed = workflow_id.replace("={{", "={").replace("}}", "}")
                params["workflowId"] = fixed
            # Also handle ={$env...} (missing =)
            elif workflow_id.startswith("{$env"):
                params["workflowId"] = "=" + workflow_id
    return node

def patch_workflow_file(filepath):
    """
    Apply all patches to a workflow file.
    Returns (changed, errors) tuple.
    """
    changed = False
    errors = []

    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            workflow = json.load(f)
    except Exception as e:
        return False, [f"Failed to load {filepath}: {e}"]

    # Patch each node
    nodes = workflow.get("nodes", [])
    for i, node in enumerate(nodes):
        node_name = node.get("name", f"node_{i}")
        node_type = node.get("type", "")

        # Fix PostgreSQL credentials
        if node_type == "n8n-nodes-base.postgres":
            if "credentials" not in node:
                add_postgres_credentials(node)
                changed = True
                print(f"  + Added credentials to: {node_name}")

        # Fix Execute Workflow syntax
        if node_type == "n8n-nodes-base.executeWorkflow":
            original = node.get("parameters", {}).get("workflowId", "")
            fix_execute_workflow_syntax(node)
            if node.get("parameters", {}).get("workflowId", "") != original:
                changed = True
                print(f"  + Fixed workflowId syntax in: {node_name}")

        # Fix JavaScript code bugs
        if node_type == "n8n-nodes-base.code":
            params = node.get("parameters", {})
            js_code = params.get("jsCode", "")
            if "denyReason !== ''" in js_code and "let denyReason" in js_code:
                # Check if denyReason is used before declaration
                deny_use_pos = js_code.find("denyReason !== ''")
                deny_decl_pos = js_code.find("let denyReason")
                if deny_use_pos < deny_decl_pos:
                    fixed_code = fix_js_deny_reason_bug(js_code)
                    if fixed_code != js_code:
                        params["jsCode"] = fixed_code
                        changed = True
                        print(f"  + Fixed denyReason bug in: {node_name}")

    if changed:
        # Write back
        with open(filepath, 'w', encoding='utf-8') as f:
            json.dump(workflow, f, indent=2)

    return changed, errors

def main():
    print("=" * 60)
    print("Workflow Patcher - Resto Bot")
    print("=" * 60)

    total_changed = 0
    total_errors = []

    for wf_file in sorted(WORKFLOWS_DIR.glob("W*.json")):
        print(f"\nPatching: {wf_file.name}")
        changed, errors = patch_workflow_file(wf_file)
        if changed:
            total_changed += 1
            print(f"  ✓ File modified")
        else:
            print(f"  - No changes needed")
        total_errors.extend(errors)

    print("\n" + "=" * 60)
    print(f"Summary: {total_changed} files modified")
    if total_errors:
        print(f"Errors: {len(total_errors)}")
        for err in total_errors:
            print(f"  ! {err}")
    print("=" * 60)

if __name__ == "__main__":
    main()
