"""Deny private mail/calendar tools for non-owner agents."""
ALLOWED_AGENTS = {"JARVIS", "ASSISTANT"}
ALLOWED_OPERATIONS = {"GMAIL_FETCH_EMAILS", "GOOGLECALENDAR_EVENTS_LIST"}

def pre_tool_call(agent: str, operation: str) -> bool:
    return agent.upper() in ALLOWED_AGENTS and operation in ALLOWED_OPERATIONS
