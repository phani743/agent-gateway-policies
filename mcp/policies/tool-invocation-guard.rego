package mcp.tool_invocation_guard

import rego.v1

# GLOBAL policy - always enforced, cannot be disabled
# Blocks dangerous MCP tools regardless of role, scope, or tenant

blocked_tools := {"delete_resource", "drop_database", "exec_shell", "drop_table", "truncate"}

deny contains msg if {
    input.request.tool in blocked_tools
    msg := sprintf("GLOBAL BLOCK: tool '%s' is prohibited by security policy", [input.request.tool])
}
