
import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";

const CONTRACT = "VoltFi";
const accounts = simnet.getAccounts();
const admin = accounts.get("deployer")!;
const userA = accounts.get("wallet_2")!;
const userB = accounts.get("wallet_3")!;
const stxSymbol = Cl.bufferFromAscii("STX");

const setPrice = (sender: string, price: number) =>
  simnet.callPublicFn(CONTRACT, "set-price", [stxSymbol, Cl.uint(price)], sender);

describe("VoltFi access control", () => {
  it("allows admin to pause/unpause and blocks state changes while paused", () => {
    const pause = simnet.callPublicFn(CONTRACT, "pause-contract", [], admin);
    expect(pause.result).toBeOk(Cl.bool(true));

    const deposit = simnet.callPublicFn(CONTRACT, "lp-deposit", [Cl.uint(100)], userA);
    expect(deposit.result).toBeErr(Cl.uint(409));

    const unpause = simnet.callPublicFn(CONTRACT, "unpause-contract", [], admin);
    expect(unpause.result).toBeOk(Cl.bool(true));
  });

  it("rejects non-admin pause attempts", () => {
    const pause = simnet.callPublicFn(CONTRACT, "pause-contract", [], userA);
    expect(pause.result).toBeErr(Cl.uint(403));
  });
});

describe("VoltFi oracle flow", () => {
  it("rejects unauthorized price updates", () => {
    const update = setPrice(userA, 1);
    expect(update.result).toBeErr(Cl.uint(403));
  });

  it("validates symbol length and price bounds", () => {
    const badSymbol = simnet.callPublicFn(
      CONTRACT,
      "set-price",
      [Cl.bufferFromAscii("STXX"), Cl.uint(100)],
      admin,
    );
    expect(badSymbol.result).toBeErr(Cl.uint(700));

    const badPrice = simnet.callPublicFn(
      CONTRACT,
      "set-price",
      [stxSymbol, Cl.uint(0)],
      admin,
    );
    expect(badPrice.result).toBeErr(Cl.uint(701));
  });

  it("allows admin to authorize oracles and update prices", () => {
    const addOracle = simnet.callPublicFn(CONTRACT, "add-oracle", [Cl.principal(userA)], admin);
    expect(addOracle.result).toBeOk(Cl.principal(userA));

    const update = setPrice(userA, 123);
    expect(update.result).toBeOk(Cl.uint(123));
  });
});

describe("VoltFi LP flow", () => {
  it("mints LP tokens on deposit and burns on withdrawal", () => {
    const depositA = simnet.callPublicFn(CONTRACT, "lp-deposit", [Cl.uint(1000)], userA);
    expect(depositA.result).toBeOk(Cl.uint(1000));

    const depositB = simnet.callPublicFn(CONTRACT, "lp-deposit", [Cl.uint(500)], userB);
    expect(depositB.result).toBeOk(Cl.uint(500));

    const balanceA = simnet.callReadOnlyFn(
      CONTRACT,
      "get-user-lp-balance",
      [Cl.principal(userA)],
      userA,
    );
    expect(balanceA.result).toBeUint(1000);

    const withdraw = simnet.callPublicFn(CONTRACT, "lp-withdraw", [Cl.uint(500)], userA);
    expect(withdraw.result).toBeOk(Cl.uint(500));

    const balanceAfter = simnet.callReadOnlyFn(
      CONTRACT,
      "get-user-lp-balance",
      [Cl.principal(userA)],
      userA,
    );
    expect(balanceAfter.result).toBeUint(500);
  });
});

describe("VoltFi vault flow", () => {
  it("enforces LTV on borrow and updates debt on repay", () => {
    expect(setPrice(admin, 1).result).toBeOk(Cl.uint(1));

    const collateral = simnet.callPublicFn(
      CONTRACT,
      "deposit-collateral",
      [Cl.uint(1000)],
      userA,
    );
    expect(collateral.result).toBeOk(Cl.uint(1000));

    const pool = simnet.callPublicFn(CONTRACT, "lp-deposit", [Cl.uint(1000)], userB);
    expect(pool.result).toBeOk(Cl.uint(1000));

    const borrowOk = simnet.callPublicFn(CONTRACT, "borrow", [Cl.uint(600)], userA);
    expect(borrowOk.result).toBeOk(Cl.uint(600));

    const borrowTooHigh = simnet.callPublicFn(CONTRACT, "borrow", [Cl.uint(200)], userA);
    expect(borrowTooHigh.result).toBeErr(Cl.uint(400));

    const repay = simnet.callPublicFn(CONTRACT, "repay-debt", [Cl.uint(200)], userA);
    expect(repay.result).toBeOk(Cl.uint(400));

    const position = simnet.callReadOnlyFn(
      CONTRACT,
      "get-user-position",
      [Cl.principal(userA)],
      userA,
    );
    expect(position.result).toBeSome(
      Cl.tuple({ collateral: Cl.uint(1000), debt: Cl.uint(400) }),
    );
  });

  it("blocks collateral withdrawals that would exceed max LTV", () => {
    expect(setPrice(admin, 1).result).toBeOk(Cl.uint(1));

    const collateral = simnet.callPublicFn(
      CONTRACT,
      "deposit-collateral",
      [Cl.uint(1000)],
      userA,
    );
    expect(collateral.result).toBeOk(Cl.uint(1000));

    const pool = simnet.callPublicFn(CONTRACT, "lp-deposit", [Cl.uint(1000)], userB);
    expect(pool.result).toBeOk(Cl.uint(1000));

    const borrowOk = simnet.callPublicFn(CONTRACT, "borrow", [Cl.uint(600)], userA);
    expect(borrowOk.result).toBeOk(Cl.uint(600));

    const withdraw = simnet.callPublicFn(
      CONTRACT,
      "withdraw-collateral",
      [Cl.uint(500)],
      userA,
    );
    expect(withdraw.result).toBeErr(Cl.uint(616));
  });
});

describe("VoltFi admin liquidation", () => {
  it("allows admin to clear a position when price drops below threshold", () => {
    expect(setPrice(admin, 100).result).toBeOk(Cl.uint(100));

    const pool = simnet.callPublicFn(CONTRACT, "lp-deposit", [Cl.uint(10000)], userB);
    expect(pool.result).toBeOk(Cl.uint(10000));

    const collateral = simnet.callPublicFn(
      CONTRACT,
      "deposit-collateral",
      [Cl.uint(100)],
      userA,
    );
    expect(collateral.result).toBeOk(Cl.uint(100));

    const borrowOk = simnet.callPublicFn(CONTRACT, "borrow", [Cl.uint(7000)], userA);
    expect(borrowOk.result).toBeOk(Cl.uint(7000));

    expect(setPrice(admin, 1).result).toBeOk(Cl.uint(1));

    const cleared = simnet.callPublicFn(
      CONTRACT,
      "admin-clear-position",
      [Cl.principal(userA)],
      admin,
    );
    expect(cleared.result).toBeOk(Cl.uint(100));

    const position = simnet.callReadOnlyFn(
      CONTRACT,
      "get-user-position",
      [Cl.principal(userA)],
      userA,
    );
    expect(position.result).toBeNone();
  });

  it("rejects non-admin liquidation attempts", () => {
    const cleared = simnet.callPublicFn(
      CONTRACT,
      "admin-clear-position",
      [Cl.principal(userA)],
      userB,
    );
    expect(cleared.result).toBeErr(Cl.uint(403));
  });
});
