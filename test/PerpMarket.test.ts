import { ethers } from "hardhat";
import { expect } from "chai";

const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");

describe("PerpMarket", function () {
  let usdc: any, priceFeed: any, pool: any, market: any;
  let trader: any, lp: any, liquidator: any;

  beforeEach(async () => {
    [lp, trader, liquidator] = await ethers.getSigners();

    const ERC20 = await ethers.getContractFactory("ERC20Mock");
    usdc = await ERC20.deploy("Mock USDC", "USDC");

    const PriceFeed = await ethers.getContractFactory("MockPriceFeed");
    priceFeed = await PriceFeed.deploy();

    const LiquidityPool = await ethers.getContractFactory("LiquidityPool");
    pool = await LiquidityPool.deploy(usdc.target);

    const PerpMarket = await ethers.getContractFactory("PerpMarket");
    market = await PerpMarket.deploy(pool.target, priceFeed.target);

    await pool.setMarket(market.target);

    await usdc.mint(lp.address, ethers.parseEther("5000"));
    await usdc.connect(lp).approve(pool.target, ethers.parseEther("5000"));
    await pool.connect(lp).deposit(ethers.parseEther("5000"));

    await usdc.mint(trader.address, ethers.parseEther("200"));
    await usdc.connect(trader).approve(market.target, ethers.parseEther("200"));
  });

  it("should open and close a long position with profit", async () => {
    await priceFeed.setPrice(BigInt(2000e8));

    await market.connect(trader).openPosition(
      ethers.parseEther("100"),
      ethers.parseUnits("2", 6),
      true
    );

    await priceFeed.setPrice(BigInt(3000e8));
    await usdc.mint(market.target, ethers.parseEther("1000"));

    const before = await usdc.balanceOf(trader.address);
    await expect(market.connect(trader).closePosition()).to.emit(market, "PositionClosed");
    const after = await usdc.balanceOf(trader.address);

    expect(after).to.be.gt(before);
  });

  it("should emit PositionLiquidated when collateral ratio too low", async () => {
    await priceFeed.setPrice(BigInt(2000e8));

    await market.connect(trader).openPosition(
      ethers.parseEther("100"),
      ethers.parseUnits("10", 6),
      true
    );

    await priceFeed.setPrice(BigInt(1000e8));
    await expect(market.connect(trader).closePosition()).to.emit(market, "PositionLiquidated");
  });

  it("should allow decreasing a position partially", async () => {
    await priceFeed.setPrice(BigInt(2000e8));
    await market.connect(trader).openPosition(
      ethers.parseEther("100"),
      ethers.parseUnits("5", 6),
      true
    );

    await priceFeed.setPrice(BigInt(2500e8));
    await usdc.mint(market.target, ethers.parseEther("1000"));

    await expect(
      market.connect(trader).decreasePosition(ethers.parseUnits("200"))
    ).to.emit(market, "PositionDecreased");
  });

  it("should open and close a short position with profit", async () => {
    await priceFeed.setPrice(BigInt(2000e8));

    await market.connect(trader).openPosition(
      ethers.parseEther("100"),
      ethers.parseUnits("2", 6),
      false
    );

    await priceFeed.setPrice(BigInt(1500e8));
    await usdc.mint(market.target, ethers.parseEther("1000"));

    const before = await usdc.balanceOf(trader.address);
    await expect(market.connect(trader).closePosition()).to.emit(market, "PositionClosed");
    const after = await usdc.balanceOf(trader.address);

    expect(after).to.be.gt(before);
  });

  it("should emit PositionLiquidated for short when price pumps", async () => {
    await priceFeed.setPrice(BigInt(2000e8));

    await market.connect(trader).openPosition(
      ethers.parseEther("100"),
      ethers.parseUnits("10", 6),
      false
    );

    await priceFeed.setPrice(BigInt(3000e8));
    await expect(market.connect(trader).closePosition()).to.emit(market, "PositionLiquidated");
  });

  it("should block LP from withdrawing reserved liquidity", async () => {
    await priceFeed.setPrice(BigInt(2000e8));
    await market.connect(trader).openPosition(
      ethers.parseEther("100"),
      ethers.parseUnits("2", 6),
      true
    );

    const lpTokenAddr = await pool.lpToken();
    const lpToken = await ethers.getContractAt("LPToken", lpTokenAddr);
    const shares = await lpToken.balanceOf(lp.address);

    await lpToken.connect(lp).approve(pool.target, shares);

    await expect(pool.connect(lp).withdraw(shares)).to.be.revertedWith("Insufficient free liquidity");
  });

  it("should increase an existing position", async () => {
    await priceFeed.setPrice(BigInt(2000e8));
    await market.connect(trader).openPosition(
      ethers.parseEther("100"),
      ethers.parseUnits("2", 6),
      true
    );

    await market.connect(trader).increasePosition(
      ethers.parseEther("50"),
      ethers.parseUnits("3", 6)
    );

    const updated = await market.positions(trader.address);
    expect(updated.size).to.be.gt(ethers.parseUnits("200"));
  });

  it("should allow adding collateral only", async () => {
    await priceFeed.setPrice(BigInt(2000e8));
    await market.connect(trader).openPosition(
      ethers.parseEther("100"),
      ethers.parseUnits("2", 6),
      true
    );

    await market.connect(trader).addCollateral(ethers.parseEther("50"));

    const updated = await market.positions(trader.address);
    expect(updated.collateral).to.be.closeTo(ethers.parseEther("150"), ethers.parseUnits("0.001", 18));
  });

  it("should enforce max utilization ratio", async () => {
    await priceFeed.setPrice(BigInt(2000e8));

    // Drain pool to reduce available liquidity
    await pool.connect(lp).withdraw(ethers.parseEther("4000"));

    const hugeCollateral = ethers.parseEther("900");
    await usdc.mint(trader.address, hugeCollateral);
    await usdc.connect(trader).approve(market.target, hugeCollateral);

    await expect(
      market.connect(trader).openPosition(
        hugeCollateral,
        ethers.parseUnits("2", 6),
        true
      )
    ).to.be.revertedWith("Exceeds utilization limit");
  });

    it("should allow third party to liquidate an undercollateralized position", async () => {
    await priceFeed.setPrice(BigInt(2000e8));
    await market.connect(trader).openPosition(
      ethers.parseEther("100"),
      ethers.parseUnits("10", 6),
      true
    );

    await priceFeed.setPrice(BigInt(1000e8));

    const before = await usdc.balanceOf(liquidator.address);

    await expect(market.connect(liquidator).liquidate(trader.address))
      .to.emit(market, "LiquidatedBy")
      .withArgs(liquidator.address, trader.address, anyValue);

    const after = await usdc.balanceOf(liquidator.address);
    expect(after).to.be.gt(before);
  });
  
});
