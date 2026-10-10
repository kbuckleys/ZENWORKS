# ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
# ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
# └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
# https://github.com/kbuckleys/
#
# THE COMMIT GRAPH — lanes for a history in topological order, one row at a
# time, so a page of 200 commits costs the same at commit 100 as at 100 000.
#
# The lanes are a list of "the commit this column is waiting for". Each row:
#
#   1. the commit takes the first column already waiting for it (or a free
#      one — a branch tip nothing above pointed at);
#   2. every OTHER column waiting for it bends into it and ends: those are
#      the children whose lines meet here;
#   3. its first parent inherits its column — so a branch stays straight;
#      each further parent (a merge) joins the column already waiting for it,
#      or takes a free one.
#
# A row is drawn in two halves, top (the edge above → the node's centre) and
# bottom (the centre → the edge below). Each half is a list of
# [fromColumn, toColumn, colour]; a straight pass-through is [c, c, colour].
# Colours stay with a line, not a column: a lane keeps the colour it was born
# with however far it travels, and a new line takes the next one. The window
# maps colour numbers onto the theme's palette.
#
# Columns are not compacted while a line still runs through them. A freed
# column is reused by the next newcomer, and trailing free columns are
# trimmed, so width follows how many lines are really open.


class Lanes:
    def __init__(self):
        self.lanes = []    # column → hash it waits for (None = free)
        self.colour = []   # column → colour number of the line in it
        self.next_colour = 0

    def _free(self):
        for i, h in enumerate(self.lanes):
            if h is None:
                return i
        self.lanes.append(None)
        self.colour.append(0)
        return len(self.lanes) - 1

    def _new_colour(self):
        c = self.next_colour
        self.next_colour += 1
        return c

    def row(self, sha, parents):
        lanes, colour = self.lanes, self.colour
        top, bottom = [], []
        mine = [i for i, h in enumerate(lanes) if h == sha]
        if mine:
            col = mine[0]
        else:
            col = self._free()
            colour[col] = self._new_colour()
        node_colour = colour[col]
        # 1 + 2: the top half — every open line arrives; ones waiting for this
        # commit bend into it, the rest pass straight through.
        for i, h in enumerate(lanes):
            if h is None:
                continue
            if h == sha:
                top.append([i, col, colour[i]])
            else:
                top.append([i, i, colour[i]])
        for i in mine[1:]:
            lanes[i] = None
        lanes[col] = None
        # 3: the parents claim columns.
        born = set()
        for n, p in enumerate(parents):
            if n == 0:
                # The first parent always carries straight on down this
                # column, even when another line is already waiting for it:
                # the two meet where the parent is drawn (step 2 there), so
                # a branch's own line stays straight and the side branch is
                # the one that bends into it — main on the left, as in
                # every git graph people know.
                lanes[col] = p
                bottom.append([col, col, node_colour])
            else:
                if p in lanes:
                    j = lanes.index(p)
                else:
                    j = self._free()
                    lanes[j] = p
                    colour[j] = self._new_colour()
                    born.add(j)
                bottom.append([col, j, colour[j]])
        for i, h in enumerate(lanes):
            # every other open line runs on down — except one born in this
            # very row, which starts at the node and has no line above it
            if h is not None and i != col and i not in born:
                bottom.append([i, i, colour[i]])
        while lanes and lanes[-1] is None:
            lanes.pop(); colour.pop()
        width = max([col + 1] + [max(a, b) + 1 for a, b, _ in top + bottom])
        return {"col": col, "colour": node_colour, "top": top,
                "bottom": bottom, "width": width}
