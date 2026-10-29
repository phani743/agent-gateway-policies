package mcp.human_in_the_loop_gate

import rego.v1

# OPTIONAL policy - enable for high-risk operations
# Requires human approval token before executing gated tools

gated_tools := {"transfer_funds", "delete_all_data", "modify_production_config", "revoke_all_tokens"}

deny contains msg if {
    input.request.tool in gated_tools
    not input.approval.human_approved
    msg := sprintf("human approval required for gated tool '%s'", [input.request.tool])
}

deny contains "approval token expired" if {
    input.approval.human_approved
    input.approval.expires_at < time.now_ns() / 1000000000
}

deny contains "approval issued by different approver than required" if {
    input.approval.human_approved
    input.approval.approver_role != "security_admin"
    input.request.tool in {"delete_all_data", "revoke_all_tokens"}
}
