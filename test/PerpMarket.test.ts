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

    await usdc.mint(lp.address, ethers.parseEther("1000"));
    await usdc.connect(lp).approve(pool.target, ethers.parseEther("1000"));
    await pool.connect(lp).deposit(ethers.parseEther("1000"));

    await usdc.mint(trader.address, ethers.parseEther("100"));
    await usdc.connect(trader).approve(market.target, ethers.parseEther("100"));
  });

  it("should open and close a long position with profit", async () => {
    await market.connect(trader).openPosition(
      ethers.parseEther("100"),
      ethers.parseUnits("2", 6),
      true
    );

    const position = await market.positions(trader.address);
    expect(position.size).to.be.gt(0);

    // Temporarily send USDC from LP to market so it has enough to pay profit : TODO
    await usdc.connect(lp).mint(market.target, ethers.parseEther("1000"));


    await priceFeed.setPrice(BigInt(3000e8));
    await market.connect(trader).closePosition();

    const finalBal = await usdc.balanceOf(trader.address);
    expect(finalBal).to.be.gt(ethers.parseEther("100")); // Profit
  });

  it("should liquidate when collateral ratio is too low", async () => {
    await market.connect(trader).openPosition(
      ethers.parseEther("100"),
      ethers.parseUnits("10", 6),
      true
    );

    await priceFeed.setPrice(BigInt(1000e8));

    await expect(market.connect(trader).closePosition()).to.be.revertedWith("Liquidated");
  });
});
