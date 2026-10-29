package mcp.prompt_injection_detection

import rego.v1

# OPTIONAL policy - enable for untrusted tool sources
# Scans MCP tool parameters for prompt injection patterns

injection_patterns := [
    `(?i)ignore\s+(previous|all|above)\s+instructions`,
    `(?i)you\s+are\s+now`,
    `(?i)system\s*:`,
    `(?i)<\s*system\s*>`,
    `(?i)forget\s+everything`,
    `(?i)new\s+instructions`,
]

deny contains msg if {
    some param_value in object.values(input.request.params)
    is_string(param_value)
    some pattern in injection_patterns
    regex.match(pattern, param_value)
    msg := sprintf("prompt injection pattern detected in tool parameter: %s", [pattern])
}
