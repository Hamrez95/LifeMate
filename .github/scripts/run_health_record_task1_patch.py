from pathlib import Path

source = Path('.github/scripts/_agent_patch_health_record_task1_source.txt').read_text()
start = source.index('          from pathlib import Path')
end = source.index('      - name: Commit focused patch')
block = source[start:end]
lines = [
    line[10:] if line.startswith('          ') else line
    for line in block.splitlines()
]
exec(compile('\n'.join(lines), 'task1_patch.py', 'exec'))
