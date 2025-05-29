import { ethers } from "hardhat";
import { expect } from "chai";

describe("PerpMarket", function () {
  let usdc: any, priceFeed: any, pool: any, market: any;
  let trader: any, lp: any;

  beforeEach(async () => {
    [lp, trader] = await ethers.getSigners();

    const ERC20 = await ethers.getContractFactory("ERC20Mock");
    usdc = await ERC20.deploy("Mock USDC", "USDC");

    const PriceFeed = await ethers.getContractFactory("MockPriceFeed");
    priceFeed = await PriceFeed.deploy();

    const LiquidityPool = await ethers.getContractFactory("LiquidityPool");
    pool = await LiquidityPool.deploy(usdc.target);

    const PerpMarket = await ethers.getContractFactory("PerpMarket");
    market = await PerpMarket.deploy(pool.target, priceFeed.target);

    await pool.setMarket(market.target);

    // LP deposits
    await usdc.mint(lp.address, ethers.parseEther("1000"));
    await usdc.connect(lp).approve(pool.target, ethers.parseEther("1000"));
    await pool.connect(lp).deposit(ethers.parseEther("1000"));

    // Trader collateral
    await usdc.mint(trader.address, ethers.parseEther("100"));
    await usdc.connect(trader).approve(market.target, ethers.parseEther("100"));
  });

  it("should open and close a long position with profit", async () => {
    await priceFeed.setPrice(BigInt(2000e8));

    await expect(
      market.connect(trader).increasePosition(
        ethers.parseEther("100"),
        ethers.parseUnits("2", 6),
        true
      )
    ).to.emit(market, "PositionOpened");

    await priceFeed.setPrice(BigInt(3000e8));
    await usdc.mint(market.target, ethers.parseEther("1000"));

    const balanceBefore = await usdc.balanceOf(trader.address);

    await expect(market.connect(trader).closePosition())
      .to.emit(market, "PositionClosed");

    const finalBal = await usdc.balanceOf(trader.address);
    expect(finalBal).to.be.gt(ethers.parseEther("100"));

    const profit = finalBal - balanceBefore;
    const pctGain = Number(profit.toString()) * 100 / Number(balanceBefore.toString());

    console.log("Profit (ETH):", ethers.formatEther(profit));
    console.log("PnL %:", pctGain);
    expect(pctGain).to.be.greaterThan(0);
  });

  it("should liquidate when collateral ratio is too low", async () => {
    await priceFeed.setPrice(BigInt(2000e8));

    await market.connect(trader).increasePosition(
      ethers.parseEther("100"),
      ethers.parseUnits("10", 6),
      true
    );

    await priceFeed.setPrice(BigInt(1000e8));

    await expect(market.connect(trader).closePosition()).to.be.revertedWith("Liquidated");
  });

  it("should allow decreasing a position partially", async () => {
    await priceFeed.setPrice(BigInt(2000e8));

    await market.connect(trader).increasePosition(
      ethers.parseEther("100"),
      ethers.parseUnits("5", 6),
      true
    );

    await priceFeed.setPrice(BigInt(2500e8));
    await usdc.mint(market.target, ethers.parseEther("1000"));

    await expect(
      market.connect(trader).decreasePosition(ethers.parseUnits("200"))
    ).to.emit(market, "PositionDecreased");

    const updated = await market.positions(trader.address);
    expect(updated.size).to.equal(ethers.parseUnits("300"));
  });

  it("should open and close a short position with profit", async () => {
    await priceFeed.setPrice(BigInt(2000e8));

    await market.connect(trader).increasePosition(
      ethers.parseEther("100"),
      ethers.parseUnits("2", 6),
      false
    );

    await priceFeed.setPrice(BigInt(1500e8));
    await usdc.mint(market.target, ethers.parseEther("1000"));

    const balanceBefore = await usdc.balanceOf(trader.address);

    await expect(market.connect(trader).closePosition())
      .to.emit(market, "PositionClosed");

    const finalBal = await usdc.balanceOf(trader.address);
    expect(finalBal).to.be.gt(ethers.parseEther("100"));

    const profit = finalBal - balanceBefore;
    const pctGain = Number(profit.toString()) * 100 / Number(balanceBefore.toString());

    console.log("Profit (ETH):", ethers.formatEther(profit));
    console.log("PnL %:", pctGain);
    expect(pctGain).to.be.greaterThan(0);
  });

  it("should liquidate a short position when price pumps", async () => {
    await priceFeed.setPrice(BigInt(2000e8));

    await market.connect(trader).increasePosition(
      ethers.parseEther("100"),
      ethers.parseUnits("10", 6),
      false
    );

    await priceFeed.setPrice(BigInt(3000e8));

    await expect(market.connect(trader).closePosition()).to.be.revertedWith("Liquidated");
  });

  it("should block LP from withdrawing reserved liquidity", async () => {
    await priceFeed.setPrice(BigInt(2000e8));

    await market.connect(trader).increasePosition(
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
});
