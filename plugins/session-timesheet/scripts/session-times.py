"""Billing timeline for a Claude Code session.

Prints one row per prompt: when it was sent, when the reply finished, and the
minutes between. Reads the session transcript, so it works retroactively.

Usage:
    python session-times.py                      # newest session in this folder's project
    python session-times.py <session-id|path>    # a specific session
    python session-times.py --project <dir>      # another project folder
    python session-times.py --csv                # comma-separated, for a spreadsheet
    python session-times.py --all                # every session in the project, newest first
"""

import datetime
import io
import json
import os
import sys

PROJECTS = os.path.join(os.path.expanduser('~'), '.claude', 'projects')


def project_dir_for_cwd():
    # Claude Code slugifies the working directory: D:\GIT\x\y -> D--GIT-x-y
    cwd = os.getcwd()
    drive, rest = os.path.splitdrive(cwd)
    slug = drive.replace(':', '-') + rest.replace('\\', '-').replace('/', '-')
    return os.path.join(PROJECTS, slug)


def newest_transcript(folder):
    files = [os.path.join(folder, f) for f in os.listdir(folder) if f.endswith('.jsonl')]
    if not files:
        raise SystemExit('No transcripts in %s' % folder)
    return max(files, key=os.path.getmtime)


def local(ts):
    return datetime.datetime.fromisoformat(ts.replace('Z', '+00:00')).astimezone()


def text_of(record):
    msg = record.get('message') or {}
    content = msg.get('content')
    if isinstance(content, list):
        parts = [p.get('text', '') for p in content
                 if isinstance(p, dict) and p.get('type') == 'text']
        content = ' '.join(parts)
    if not isinstance(content, str):
        return ''
    return ' '.join(content.split())


def is_real_prompt(record, body):
    if record.get('type') != 'user' or record.get('isMeta'):
        return False
    if not body:
        return False
    # Slash commands, their stdout, and tool results are not billable prompts.
    for marker in ('<local-command', '<command-name>', '[Request interrupted'):
        if marker in body:
            return False
    msg = record.get('message') or {}
    content = msg.get('content')
    if isinstance(content, list):
        if any(isinstance(p, dict) and p.get('type') == 'tool_result' for p in content):
            return False
    return True


def turns(path):
    rows = []
    pending = None
    last_assistant = None
    with io.open(path, encoding='utf-8') as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except ValueError:
                continue
            stamp = record.get('timestamp')
            if not stamp:
                continue
            kind = record.get('type')
            if kind == 'assistant':
                last_assistant = stamp
                continue
            body = text_of(record)
            if not is_real_prompt(record, body):
                continue
            if pending is not None:
                rows.append((pending[0], last_assistant, pending[1]))
            pending = (stamp, body)
            last_assistant = None
    if pending is not None:
        rows.append((pending[0], last_assistant, pending[1]))
    return rows


def report(path, as_csv):
    rows = turns(path)
    if not rows:
        return 0.0
    total = 0.0
    if as_csv:
        print('date,prompt_sent,reply_done,minutes,prompt')
    else:
        print('\n%s' % os.path.basename(path))
        print('%-10s %-6s %-6s %6s  %s' % ('Date', 'Sent', 'Done', 'Mins', 'Prompt'))
    for start, end, body in rows:
        begin = local(start)
        finish = local(end) if end else begin
        minutes = (finish - begin).total_seconds() / 60.0
        total += minutes
        if as_csv:
            safe = body.replace('"', "'")
            print('%s,%s,%s,%.1f,"%s"' % (begin.strftime('%Y-%m-%d'),
                                          begin.strftime('%H:%M'),
                                          finish.strftime('%H:%M'),
                                          minutes, safe))
        else:
            print('%-10s %-6s %-6s %6.1f  %s' % (begin.strftime('%Y-%m-%d'),
                                                 begin.strftime('%H:%M'),
                                                 finish.strftime('%H:%M'),
                                                 minutes, body[:58]))
    if not as_csv:
        span = (local(rows[-1][1] or rows[-1][0]) - local(rows[0][0])).total_seconds() / 60.0
        print('%-24s %6.1f  (%d prompts, %.1f min elapsed)' % ('TOTAL working', total, len(rows), span))
    return total


def main():
    args = [a for a in sys.argv[1:]]
    as_csv = '--csv' in args
    every = '--all' in args
    args = [a for a in args if not a.startswith('--') or a == '--project']

    folder = project_dir_for_cwd()
    if '--project' in args:
        folder = args[args.index('--project') + 1]
        args = []

    if every:
        files = sorted((os.path.join(folder, f) for f in os.listdir(folder) if f.endswith('.jsonl')),
                       key=os.path.getmtime, reverse=True)
        grand = sum(report(f, as_csv) for f in files)
        if not as_csv:
            print('\nGRAND TOTAL %.1f min (%.2f h)' % (grand, grand / 60.0))
        return

    if args:
        target = args[0]
        if not os.path.exists(target):
            target = os.path.join(folder, target + '.jsonl')
    else:
        target = newest_transcript(folder)
    report(target, as_csv)


if __name__ == '__main__':
    main()
