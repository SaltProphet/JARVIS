import json
import sqlite3
import sys

db = sys.argv[1]
action = sys.argv[2]
con = sqlite3.connect(db, timeout=5)
con.execute("CREATE TABLE IF NOT EXISTS agent_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, agent_name TEXT NOT NULL, task_description TEXT NOT NULL, model_used TEXT, status TEXT NOT NULL, created_at TEXT NOT NULL)")
con.execute("CREATE INDEX IF NOT EXISTS idx_agent_logs_created_at ON agent_logs(created_at DESC)")
if action == "add":
    agent = {"DEFAULT": "JARVIS"}.get(sys.argv[3].upper(), sys.argv[3].upper())
    if agent not in ("JARVIS", "DEV", "RESEARCH", "ASSISTANT"):
        raise SystemExit("invalid agent")
    description = sys.argv[4][:500]
    status = sys.argv[5]
    if status not in ("completed", "failed", "running"):
        raise SystemExit("invalid status")
    model = sys.argv[6] if len(sys.argv) > 6 and sys.argv[6] else None
    con.execute("INSERT INTO agent_logs(agent_name,task_description,model_used,status,created_at) VALUES(?,?,?,?,datetime('now'))", (agent, description, model, status))
    con.commit()
elif action == "get":
    rows = con.execute("SELECT agent_name, task_description, model_used, status, created_at FROM agent_logs ORDER BY id")
    print(json.dumps([dict(zip([d[0] for d in rows.description], row)) for row in rows]))
con.close()
