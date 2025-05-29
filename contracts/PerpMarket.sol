// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./LiquidityPool.sol";

interface IPriceFeed {
    function getPrice() external view returns (uint256); // returns price in 1e8 format
}

contract PerpMarket {
    struct Position {
        uint256 size;      // in USD, 1e6 precision
        uint256 entryPrice; // in 1e8
        uint256 collateral; // in collateral token units
        bool isLong;
    }

    mapping(address => Position) public positions;
    LiquidityPool public pool;
    IERC20 public collateralToken;
    IPriceFeed public priceFeed;

    uint256 public minCollateralRatio = 10e4; // 10%, in basis points
    uint256 public fundingRate = 50; // 0.005% per hour (0.00005 * 1e6)

    constructor(address _pool, address _feed) {
        pool = LiquidityPool(_pool);
        collateralToken = IERC20(pool.collateralToken());
        priceFeed = IPriceFeed(_feed);
    }

    function openPosition(uint256 collateralAmount, uint256 leverage, bool isLong) external {
        require(collateralAmount > 0, "Zero collateral");
        require(leverage >= 1e6 && leverage <= 10e6, "1x to 10x");

        uint256 price = priceFeed.getPrice(); // e.g., 2000 * 1e8
        require(price > 0, "Invalid price");

        uint256 sizeUsd = (collateralAmount * leverage) / 1e6;

        // Lock funds
        require(collateralToken.transferFrom(msg.sender, address(this), collateralAmount), "Transfer failed");
        collateralToken.approve(address(pool), collateralAmount);
        pool.reserve(collateralAmount);

        positions[msg.sender] = Position({
            size: sizeUsd,
            entryPrice: price,
            collateral: collateralAmount,
            isLong: isLong
        });
    }

    function closePosition() external {
        Position memory p = positions[msg.sender];
        require(p.size > 0, "No position");

        uint256 currentPrice = priceFeed.getPrice();

        // Use signed math for PnL to handle losses
        int256 pnl;
        if (p.isLong) {
            pnl = int256(p.size * currentPrice / p.entryPrice) - int256(p.size);
        } else {
            pnl = int256(p.size) - int256(p.size * currentPrice / p.entryPrice);
        }

        int256 finalCollateral = int256(p.collateral) + pnl;

        // Liquidation condition (if collateral falls below threshold)
        require(
            finalCollateral > 0 &&
            uint256(finalCollateral) * 1e6 / p.size >= minCollateralRatio,
            "Liquidated"
        );

        // Release funds from the pool
        pool.release(p.collateral);
        delete positions[msg.sender];

        // Transfer final collateral back to user
        collateralToken.transfer(msg.sender, uint256(finalCollateral));
    }

    function getPnL(address user) external view returns (int256) {
        Position memory p = positions[user];
        if (p.size == 0) return 0;

        uint256 currentPrice = priceFeed.getPrice();
        if (p.isLong) {
            return int256((p.size * currentPrice / p.entryPrice)) - int256(p.size);
        } else {
            return int256(p.size) - int256((p.size * currentPrice / p.entryPrice));
        }
    }
}
