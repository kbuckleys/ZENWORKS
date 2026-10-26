// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// the window switcher's pure half: most recently used first, the order at
// login, where a press lands.

"use strict";

module.exports = {
  module: "morpheus/switcher.js",
  cases: (S, t) => {
    t.eq("touch: to the front", S.touch(["a", "b", "c"], "c"), ["c", "a", "b"]);
    t.eq("touch: new", S.touch(["a"], "b"), ["b", "a"]);
    t.eq("touch: nothing", S.touch(["a"], ""), ["a"]);
    t.eq("seed: by history, unknown dropped",
      S.seed([{ address: "b", history: 1 }, { address: "a", history: 0 }, { address: "x", history: -1 }]), ["a", "b"]);
    t.eq("ordered: known first, new after as given",
      S.ordered([{ address: "n1" }, { address: "b" }, { address: "a" }, { address: "n2" }], ["a", "b"]).map((w) => w.address),
      ["a", "b", "n1", "n2"]);
    t.eq("first stop: the window before", S.firstStop(1, 4), 1);
    t.eq("first stop back: the oldest", S.firstStop(-1, 4), 3);
    t.eq("first stop: one window", [S.firstStop(1, 1), S.firstStop(-1, 1), S.firstStop(1, 0)], [0, 0, 0]);
    t.eq("step: wraps", [S.stepFrom(3, 1, 4), S.stepFrom(0, -1, 4), S.stepFrom(1, 1, 4)], [0, 3, 2]);
    const first = S.peekPlan(["a", "b", "c"], "b", []);
    t.eq("peek: all but the pick fade", [first.add, first.drop], [["a", "c"], []]);
    const next = S.peekPlan(["a", "b", "c"], "c", first.tagged);
    t.eq("peek: a step swaps just two", [next.add, next.drop], [["b"], ["c"]]);
    const off = S.peekPlan(["a", "b", "c"], "", next.tagged);
    t.eq("peek: put away, every tag off", [off.add, off.drop, off.tagged], [[], ["a", "b"], []]);
    t.eq("peek: a closed window's tag goes too", S.peekPlan(["a"], "a", ["b"]).drop, ["b"]);
  }
};
