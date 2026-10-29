package mcp.data_exfiltration_guard

import rego.v1

# OPTIONAL policy - enable in read-heavy environments
# Blocks bulk data reads exceeding thresholds

bulk_read_tools := {"list_all_records", "export_dataset", "dump_table", "get_all_users"}

threshold_rows := 1000

deny contains msg if {
    input.request.tool in bulk_read_tools
    input.request.params.limit
    input.request.params.limit > threshold_rows
    msg := sprintf("bulk read of %d rows exceeds threshold of %d for tool %s", [input.request.params.limit, threshold_rows, input.request.tool])
}

deny contains msg if {
    input.request.tool in bulk_read_tools
    not input.request.params.limit
    msg := sprintf("bulk read tool %s called without explicit row limit", [input.request.tool])
}
