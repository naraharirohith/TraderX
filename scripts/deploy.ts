import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with:", deployer.address);

  // Deploy a mock USDC token (18 decimals for simplicity)
  const ERC20 = await ethers.getContractFactory("ERC20");
  const usdc = await ERC20.deploy("Mock USDC", "USDC");
  await usdc.deployed();
  console.log("Mock USDC deployed at:", usdc.address);

  // Deploy LiquidityPool
  const LiquidityPool = await ethers.getContractFactory("LiquidityPool");
  const pool = await LiquidityPool.deploy(usdc.address);
  await pool.deployed();
  console.log("LiquidityPool deployed at:", pool.address);

  // Deploy MockPriceFeed
  const PriceFeed = await ethers.getContractFactory("MockPriceFeed");
  const priceFeed = await PriceFeed.deploy();
  await priceFeed.deployed();
  console.log("PriceFeed deployed at:", priceFeed.address);

  // Deploy PerpMarket
  const PerpMarket = await ethers.getContractFactory("PerpMarket");
  const market = await PerpMarket.deploy(pool.address, priceFeed.address);
  await market.deployed();
  console.log("PerpMarket deployed at:", market.address);

  // Link the market and pool
  await pool.setMarket(market.address);
  console.log("Market linked to pool");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
