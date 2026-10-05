#!/usr/bin/env python3
"""Propose names for the routines (and data blocks) the disassembly still
calls sub_XXXXXX (dat_XXXXXX).

Reads the split listing (out/asm) and writes symbol lines for
issdeluxe_symbols.txt:

1. Entries of the named dispatch tables are named after their slot
   (strategy_*, restart_setup_*, restart_resume_*, cmd_XX).
2. A routine that is only ever installed (obj_update / obj_think / obj_draw),
   called or jumped to from the code of one named routine is part of it:
   <owner>_<n>, or <owner>_<action> when it starts one player action.
3. Every other routine becomes a root named <area>_<category>_<address>:
   area = the part of the ROM it is in (keeper, player, ball, ai, menu, ...),
   category = what it visibly does (start_<action>, state, draw, load, text,
   speech, sound, check, input, func). Step 2 is repeated from these roots.
4. A data block used by one routine is <routine>_data; one used by several
   is <area>_data_<address>, with its users in the comment.

Names in the symbols file and in names.txt (old new comment, one per line,
for routines named by hand) are never changed.

    name_routines.py out/asm issdeluxe_symbols.txt [names.txt] > generated.txt
"""
import glob
import re
import sys
from collections import defaultdict

AUTO = re.compile(r"^(sub|main|boot|sound)_[0-9A-F]{6}$")
LABEL = re.compile(r"^([A-Za-z_]\w*):")
INSTALL = re.compile(r"move\.l\s+#(\w+),\(?(?:g_\w+\+)?obj_(update|think|draw)")
BRANCH = re.compile(r"\b(jsr|bsr(?:\.[sw])?|jmp|bra(?:\.[sw])?|b(?:eq|ne|pl|mi|ge|gt|le|lt|cc|cs|hi|ls|vc|vs)"
                    r"(?:\.[sw])?)\s+\(?(\w+)\)?")
DCL = re.compile(r"^\s*dc\.l\s+(\w+)")
ADDRREF = re.compile(r"(?:lea|move\.l|movea\.l|pea)\s+#?\(?(sub_[0-9A-F]{6})\)?")
ACTION = re.compile(r"move\.w\s+#\$([0-9A-F]+),obj_action\(a5\)")
DATAREF = re.compile(r"\b((?:dat|\w+_data)_[0-9A-F]{6})\b")

ACTIONS = ["stand", "ready stance", "jog on the spot", "turn step", "side step", "shuffle step", "run", "walk",
           "run crouched", "sprint", "pull up", "turn", "knee trap", "short poke", "power kick", "side-foot pass",
           "kick left", "kick right", "backheel", "standing header", "overhead kick", "jumping header",
           "diving header", "slide", "sit after a slide", "get up", "stumble", "dejected", "stand still",
           "hands over face", "fist pump", "knee slide", "arm up", "dance", "jump", "full-length dive",
           "fall backwards", "bend down", "wall", "lying injured", "lose the ball", "feint left", "feint right",
           "arm raised", "stop the ball", "leap", "flick up", "chip", "keeper on the ball", "knock on",
           "wall shuffle", "walk arms out", "bend over", "belly slide"]
RESTARTS = ["throw_in", "goal_kick", "corner", "kickoff", "match_start", "free_kick", "penalty", "penalty_spot",
            "own_goal", "half_time", "time_up", "goal", "practice", "practice_target"]
STRATS = ["all_out_attack", "push_centre", "push_wings", "counter_attack", "all_out_defence", "press_up",
          "zone_press", "offside_trap"]
TABLES = {
    "tbl_team_strategies": (lambda i: "strategy_" + STRATS[i], "Strategy %d (tbl_team_strategies)"),
    "tbl_restart_setup": (lambda i: "restart_setup_" + RESTARTS[i], "Restart setup for g_restart_type %d (tbl_restart_setup)"),
    "tbl_restart_resume": (lambda i: "restart_resume_" + RESTARTS[i], "Match resumes with g_restart_type %d (tbl_restart_resume)"),
    "tbl_script_commands": (lambda i: "cmd_%02X" % i, "Sound script command $%02X (tbl_script_commands)"),
}
AREAS = [(0x000000, "sys"), (0x001DF0, "keeper"), (0x00534C, "player"), (0x00A000, "ball"), (0x00C536, "ai"),
         (0x010650, "match"), (0x01487E, "rules"), (0x018890, "matchflow"), (0x01C7A4, "engine"),
         (0x020408, "misc"), (0x03B09E, "menu"), (0x05D72A, "data"), (0x144318, "boot"), (0x14A150, "data"),
         (0x1FD954, "sound")]
KIND = {"update": "state set by", "think": "think set by", "draw": "draw set by", "call": "called by",
        "jump": "jumped to from", "table": "listed in", "ref": "address taken by"}


def slug(s):
    return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")


def addr_of(n):
    return int(n[-6:], 16)


def area(a):
    name = "sys"
    for start, n in AREAS:
        if a >= start:
            name = n
    return name


def parse(asm):
    funcs, order = {}, []
    cur = None
    for path in sorted(glob.glob(asm + "/**/*.asm", recursive=True)):
        for line in open(path, errors="replace"):
            m = LABEL.match(line)
            if m:
                name = m.group(1)
                if name.startswith("loc_"):
                    continue
                cur = {"name": name, "out": [], "actions": set(), "table": name.startswith("dat_"), "body": [],
                       "data": set()}
                funcs[name] = cur
                if not cur["table"]:
                    order.append(name)
                continue
            if cur is None:
                continue
            text = line.split(";")[0].strip()
            if text and len(cur["body"]) < 60:
                cur["body"].append(text)
            cur["data"].update(DATAREF.findall(text))
            m = INSTALL.search(line)
            if m:
                cur["out"].append((m.group(1), m.group(2)))
                continue
            m = DCL.match(line)
            if m:
                cur["out"].append((m.group(1), "table"))
                continue
            m = BRANCH.search(text)
            if m:
                cur["out"].append((m.group(2), "call" if m.group(1).startswith(("jsr", "bsr")) else "jump"))
            m = ADDRREF.search(text)
            if m:
                cur["out"].append((m.group(1), "ref"))
            m = ACTION.search(text)
            if m:
                cur["actions"].add(int(m.group(1), 16))
    return funcs, order


def category(f, a):
    b = f["body"]
    text = "\n".join(b)
    acts = sorted({int(x, 16) for x in ACTION.findall(text)})
    if b and re.match(r"move\.l\s+#\w+,obj_update\(a5\)", b[0]):
        if len(acts) == 1 and acts[0] < len(ACTIONS):
            return "start_" + slug(ACTIONS[acts[0]])
        return "state"
    if "sprite_alloc" in text:
        return "draw"
    if "dma_queue_add" in text or "decompress_factor5" in text:
        return "load"
    if "g_text_nametable" in text or "text_draw" in text:
        return "text"
    if "speech_queue_push" in text:
        return "speech"
    if "sound_play" in text and area(a) != "sound":
        return "sound"
    if re.search(r"move\.w\s+#\$FFFF,d0", text) and "rts" in text:
        return "check"
    if "g_pad" in text:
        return "input"
    return "func"


def main():
    asm, symfile = sys.argv[1], sys.argv[2]
    manual = {}
    if len(sys.argv) > 3:
        for line in open(sys.argv[3]):
            if line.strip():
                old, new, note = line.rstrip("\n").split(" ", 2)
                manual[old] = (new, note)
    funcs, order = parse(asm)
    existing = set(funcs)
    for line in open(symfile):
        m = re.match(r"^\s*(\w+)\s*=", line)
        if m:
            existing.add(m.group(1))

    refs = defaultdict(list)
    for f in funcs.values():
        for t, kind in f["out"]:
            if t != f["name"]:
                refs[t].append((f["name"], kind))

    auto = [n for n in order if AUTO.match(n)]
    name = dict(manual)           # old -> (new, note)
    owner = {n: n for n in order if not AUTO.match(n)}
    for old, (new, _) in manual.items():
        owner[old] = new
    for tname, (fn, note) in TABLES.items():
        if tname not in funcs:
            continue
        entries = [t for t, kind in funcs[tname]["out"] if kind == "table"]
        for i, t in enumerate(entries):
            if AUTO.match(t) and t not in name:
                dups = [j for j, x in enumerate(entries) if x == t][1:]
                name[t] = (fn(i), note % i + ("; also entries " + ", ".join(map(str, dups)) if dups else ""))
                owner[t] = name[t][0]

    def owners_of(n):
        os_ = set()
        for r, kind in refs.get(n, []):
            if funcs.get(r, {}).get("table"):
                trs = refs.get(r, [])
                os_ |= {owner.get(x, ("?", x)) for x, _ in trs} if trs else {("?", r)}
            else:
                os_.add(owner.get(r, ("?", r)))
        return os_

    taken = set(existing) | {v[0] for v in name.values()}
    members = defaultdict(list)
    while True:
        changed = True
        while changed:                               # propagate single ownership
            changed = False
            for n in auto:
                if n in owner:
                    continue
                os_ = owners_of(n)
                if len(os_) == 1 and not isinstance(next(iter(os_)), tuple):
                    owner[n] = next(iter(os_))
                    members[owner[n]].append(n)
                    changed = True
        left = [n for n in auto if n not in owner]
        if not left:
            break
        # New roots: no referrers, or referred to from several places.
        roots = [n for n in left if len(owners_of(n)) != 1] or left[:1]
        for n in roots:
            a = addr_of(n)
            new = "%s_%s_%06X" % (area(a), category(funcs[n], a), a)
            taken.add(new)
            name[n] = (new, None)
            owner[n] = new

    # Members: <owner>_<action> or <owner>_<n>, in address order.
    for o, ms in members.items():
        k = 0
        for n in sorted(ms, key=addr_of):
            if n in name:
                continue
            acts = sorted(funcs[n]["actions"])
            if any(kind == "draw" for _, kind in refs[n]):
                suffix = "draw"
            elif len(acts) == 1 and acts[0] < len(ACTIONS):
                suffix = slug(ACTIONS[acts[0]])
            else:
                suffix = None
            if suffix:
                new, j = "%s_%s" % (o, suffix), 2
                while new in taken:
                    new, j = "%s_%s%d" % (o, suffix, j), j + 1
            else:
                k += 1
                new = "%s_%d" % (o, k)
                while new in taken:
                    k += 1
                    new = "%s_%d" % (o, k)
            taken.add(new)
            name[n] = (new, None)

    def show(r):
        return name[r][0] if r in name else r

    # Data blocks: named after the routine that uses them.
    users = defaultdict(set)
    for f in funcs.values():
        if not f["table"]:
            for d in f["data"]:
                users[d].add(f["name"])
    counts = defaultdict(int)
    for d in sorted(users, key=addr_of):
        if d in existing and not re.match(r"^(dat|\w+_data)_[0-9A-F]{6}$", d):
            continue
        us = sorted({show(u) for u in users[d]})
        if len(us) == 1:
            base = us[0] + "_data"
            counts[base] += 1
            new = base if counts[base] == 1 else "%s%d" % (base, counts[base])
            while new in taken:
                counts[base] += 1
                new = "%s%d" % (base, counts[base])
            note = "Data used by " + us[0]
        else:
            new = "%s_data_%06X" % (area(addr_of(d)), addr_of(d))
            note = "Data used by " + ", ".join(us[:4]) + (" (+%d)" % (len(us) - 4) if len(us) > 4 else "")
        taken.add(new)
        name[d] = (new, note)

    # Data blocks only listed in other tables: <table>_<index> (repeated
    # so that nested tables follow their parents).
    AUTOD = re.compile(r"^(dat|\w+_data)_[0-9A-F]{6}$")
    changed = True
    while changed:
        changed = False
        for t in sorted((f for f in funcs.values() if f["table"] or not AUTO.match(f["name"])),
                        key=lambda f: f["name"]):
            if not t["table"] and t["name"] not in existing:
                continue
            tn = show(t["name"])
            if AUTOD.match(tn):
                continue                              # parent not named yet
            entries = [x for x, kind in t["out"] if kind == "table"]
            for i, d in enumerate(entries):
                if AUTOD.match(d) and d not in name and d in funcs and funcs[d]["table"]:
                    new = "%s_%d" % (tn, i)
                    while new in taken:
                        new += "_"
                    taken.add(new)
                    name[d] = (new, "Entry %d of %s" % (i, tn))
                    changed = True

    # Notes last, so that they cite the final names of the tables too.
    for n, (new, note) in list(name.items()):
        if note is not None:
            continue
        how = sorted({(KIND[kind], show(r)) for r, kind in refs.get(n, [])})
        o = owner.get(n)
        if o and o != new:
            note = "Part of %s: " % o
        elif how:
            note = "Shared: "
        else:
            note = "No static reference (reached through a computed jump, or unused)"
        note += "; ".join("%s %s" % h for h in how[:4]) + (" (+%d)" % (len(how) - 4) if len(how) > 4 else "")
        acts = sorted(funcs[n]["actions"])
        if acts:
            note += "; action " + ", ".join("%d %s" % (a, ACTIONS[a]) if a < len(ACTIONS) else str(a) for a in acts)
        name[n] = (new, note)

    for n in sorted(name, key=addr_of):
        new, note = name[n]
        print("%-27s = $%06X ; %s" % (new, addr_of(n), note))
    nd = sum(1 for n in name if not AUTO.match(n))
    print("%d routines and %d data blocks named" % (len(name) - nd, nd), file=sys.stderr)


if __name__ == "__main__":
    main()
