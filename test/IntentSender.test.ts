// test/IntentSender.test.ts
import { ethers } from "hardhat";
import { expect } from "chai";

describe("IntentSender Cross-Chain Tests", function () {
  let intentSender: any, vaultReceiver: any, pool: any, market: any, usdc: any, priceFeed: any;
  let user: any, router: any, fakeRouter: any;

  beforeEach(async () => {
    [router, user, fakeRouter] = await ethers.getSigners();

    const ERC20 = await ethers.getContractFactory("ERC20Mock");
    usdc = await ERC20.deploy("Mock USDC", "USDC");

    const PriceFeed = await ethers.getContractFactory("MockPriceFeed");
    priceFeed = await PriceFeed.deploy();
    await priceFeed.setPrice(BigInt(2000e8));

    const LiquidityPool = await ethers.getContractFactory("LiquidityPool");
    pool = await LiquidityPool.deploy(usdc.target);

    const PerpMarket = await ethers.getContractFactory("PerpMarket");
    market = await PerpMarket.deploy(pool.target, priceFeed.target);
    await pool.setMarket(market.target);

    const VaultReceiver = await ethers.getContractFactory("VaultReceiver");
    vaultReceiver = await VaultReceiver.deploy(market.target, router.address);

    const IntentSender = await ethers.getContractFactory("IntentSender");
    intentSender = await IntentSender.deploy(router.address);

    await usdc.mint(user.address, ethers.parseEther("100"));
    await usdc.connect(user).approve(intentSender.target, ethers.parseEther("100"));
  });

  it("should send and receive open long position intent", async () => {
    const encoded = await intentSender.encodeIntent(
      user.address,
      0, // Action: Open
      ethers.parseEther("100"),
      ethers.parseUnits("2", 6),
      true
    );

    // Simulate receiving it on other chain
    await usdc.mint(market.target, ethers.parseEther("100"));
    await vaultReceiver.ccipReceive(123, encoded);

    const pos = await market.positions(user.address);
    expect(pos.size).to.equal(ethers.parseUnits("200"));
    expect(pos.isLong).to.be.true;
  });

  it("should reject open with invalid leverage", async () => {
    const encoded = await intentSender.encodeIntent(
      user.address,
      0,
      ethers.parseEther("100"),
      ethers.parseUnits("20", 6),
      true
    );

    await expect(vaultReceiver.ccipReceive(123, encoded)).to.be.revertedWith("1x to 10x");
  });

  it("should open and close short position via intent", async () => {
    const open = await intentSender.encodeIntent(
      user.address,
      0,
      ethers.parseEther("100"),
      ethers.parseUnits("2", 6),
      false
    );

    await usdc.mint(market.target, ethers.parseEther("100"));
    await vaultReceiver.ccipReceive(123, open);

    const close = await intentSender.encodeIntent(user.address, 1, 0, 0, false);
    await priceFeed.setPrice(BigInt(1500e8));
    await vaultReceiver.ccipReceive(123, close);

    const bal = await usdc.balanceOf(user.address);
    expect(bal).to.be.gt(ethers.parseEther("100"));
  });

  it("should revert liquidation scenario", async () => {
    const open = await intentSender.encodeIntent(
      user.address,
      0,
      ethers.parseEther("100"),
      ethers.parseUnits("10", 6),
      true
    );

    await usdc.mint(market.target, ethers.parseEther("100"));
    await vaultReceiver.ccipReceive(123, open);

    await priceFeed.setPrice(BigInt(1000e8));
    const close = await intentSender.encodeIntent(user.address, 1, 0, 0, true);
    await expect(vaultReceiver.ccipReceive(123, close)).to.be.revertedWith("Liquidated");
  });

  it("should reject zero collateral", async () => {
    const encoded = await intentSender.encodeIntent(user.address, 0, 0, ethers.parseUnits("2", 6), true);
    await expect(vaultReceiver.ccipReceive(123, encoded)).to.be.revertedWith("Zero collateral");
  });
});
