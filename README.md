# Todoist Today for Omarchy Quattro

A theme-native Todoist day calendar for the Omarchy bar. It puts date-only
tasks in an all-day strip, lays timed tasks onto a day rail, resolves overlaps
into lanes, and follows the active Omarchy theme.

## Install

```bash
omarchy plugin add https://github.com/Erscheinung/omarchy-todoist-today.git --enable --yes
~/.config/omarchy/plugins/io.github.erscheinung.todoist-today/scripts/configure-token
```

Paste a [Todoist personal API token](https://todoist.com/app/settings/integrations/developer)
when prompted. The setup command stores it in `~/.config/todoist/omarchy-token`
with mode `600`; it is never written inside the plugin checkout or placed in a
process argument.

Runtime dependencies are `curl` and `jq`, both included with Omarchy.

## Use

- Left-click the bar count to toggle the calendar.
- Middle-click refreshes; right-click opens Todoist Today.
- Click a task to open it, or its circle to complete it.
- Use `j`/`k` and Enter in the panel, or `r` (refresh), `n` (now), `o` (open), and Escape.

The panel refreshes every five minutes and when opened after two minutes of
inactivity. Completing a recurring task advances it exactly as Todoist does.

## Remove

```bash
omarchy plugin remove io.github.erscheinung.todoist-today --yes
```

The credential is intentionally kept when the plugin is removed. To remove it
too, delete `~/.config/todoist/omarchy-token`.

## Privacy and permissions

This plugin makes HTTPS requests only to `api.todoist.com`. It reads today's
active tasks and project names, and sends a close request only when you click a
task's completion circle. Task contents stay in memory and are not cached.

## Development

```bash
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell BarWidget.qml Panel.qml
bash -n scripts/todoist scripts/configure-token
```
