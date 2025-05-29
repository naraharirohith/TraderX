import { ethers } from "hardhat";
import { expect } from "chai";

describe("LiquidityPool", function () {
  let usdc: any, lpToken: any, pool: any;
  let alice: any, bob: any;
  let aliceInitialBalance: any;

  beforeEach(async () => {
    [alice, bob] = await ethers.getSigners();

    const ERC20 = await ethers.getContractFactory("ERC20Mock");
    usdc = await ERC20.deploy("Mock USDC", "USDC");

    const aliceInitialBalance = await usdc.balanceOf(alice.address);

    const LiquidityPool = await ethers.getContractFactory("LiquidityPool");
    pool = await LiquidityPool.deploy(usdc.target);

    // Mint tokens and approve
    await usdc.mint(alice.address, ethers.parseEther("1000"));
    await usdc.mint(bob.address, ethers.parseEther("1000"));

    await usdc.connect(alice).approve(pool.target, ethers.parseEther("1000"));
    await usdc.connect(bob).approve(pool.target, ethers.parseEther("1000"));
  });

  it("should allow deposit and mint LP tokens", async () => {
    await pool.connect(alice).deposit(ethers.parseEther("500"));

    const lpTokenAddr = await pool.lpToken();
    const lp = await ethers.getContractAt("LPToken", lpTokenAddr);

    const balance = await lp.balanceOf(alice.address);
    expect(balance).to.equal(ethers.parseEther("500"));
  });

  it("should allow withdrawal and burn LP tokens", async () => {
    await pool.connect(alice).deposit(ethers.parseEther("500"));

    const lpTokenAddr = await pool.lpToken();
    const lp = await ethers.getContractAt("LPToken", lpTokenAddr);

    await lp.connect(alice).approve(pool.target, ethers.parseEther("500"));
    await pool.connect(alice).withdraw(ethers.parseEther("500"));

    const bal = await usdc.balanceOf(alice.address);
    expect(bal).to.equal((ethers.parseEther("1000"))); // Fully withdrawn
  });

  it("should not allow withdrawing reserved liquidity", async () => {
    await pool.connect(alice).deposit(ethers.parseEther("1000"));

    await pool.setMarket(bob.address); // Fake market
    await pool.connect(bob).reserve(ethers.parseEther("800"));

    const lpTokenAddr = await pool.lpToken();
    const lp = await ethers.getContractAt("LPToken", lpTokenAddr);

    await lp.connect(alice).approve(pool.target, ethers.parseEther("1000"));

    await expect(pool.connect(alice).withdraw(ethers.parseEther("1000"))).to.be.revertedWith(
      "Insufficient free liquidity"
    );
  });
});
