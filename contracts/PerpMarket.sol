// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./LiquidityPool.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";



interface IPriceFeed {
    function getPrice() external view returns (uint256); // returns price in 1e8 format
}

contract PerpMarket {
    AggregatorV3Interface internal priceFeed;

    struct Position {
        uint256 size;      // in USD, 1e6 precision
        uint256 entryPrice; // in 1e8
        uint256 collateral; // in collateral token units
        bool isLong;
    }

    mapping(address => Position) public positions;
    LiquidityPool public pool;
    IERC20 public collateralToken;
    

    uint256 public minCollateralRatio = 10e4; // 10%, in basis points
    uint256 public fundingRate = 50; // 0.005% per hour (0.00005 * 1e6)

    event PositionOpened(address indexed user, uint256 size, uint256 collateral, uint256 entryPrice, bool isLong);
    event PositionClosed(address indexed user, uint256 finalCollateral, int256 pnl);
    event PositionDecreased(address indexed user, uint256 reducedSize, uint256 remainingSize, int256 pnl);

    constructor(address _pool, address _priceFeed) {
        pool = LiquidityPool(_pool);
        collateralToken = IERC20(pool.collateralToken());
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    function getLatestPrice() public view returns (int256) {
        (
            , 
            int256 price,
            ,
            ,
            
        ) = priceFeed.latestRoundData();
        return price;
    }

    function openPosition(uint256 collateralAmount, uint256 leverage, bool isLong) external {
        require(positions[msg.sender].size == 0, "Position already open");
        require(collateralAmount > 0, "Zero collateral");
        require(leverage >= 1e6 && leverage <= 10e6, "1x to 10x");

        uint256 price = uint256(getLatestPrice());
        require(price > 0, "Invalid price");

        uint256 sizeUsd = (collateralAmount * leverage) / 1e6;

        require(collateralToken.transferFrom(msg.sender, address(this), collateralAmount), "Transfer failed");
        collateralToken.approve(address(pool), collateralAmount);
        pool.reserve(collateralAmount);

        positions[msg.sender] = Position({
            size: sizeUsd,
            entryPrice: price,
            collateral: collateralAmount,
            isLong: isLong
        });

        emit PositionOpened(msg.sender, sizeUsd, collateralAmount, price, isLong);
    }

    function increasePosition(uint256 additionalCollateral, uint256 additionalLeverage) external {
        Position storage p = positions[msg.sender];
        require(p.size > 0, "No existing position");
        require(additionalCollateral > 0, "Zero collateral");
        require(additionalLeverage >= 1e6 && additionalLeverage <= 10e6, "Invalid leverage");

        uint256 price = uint256(getLatestPrice());
        require(price > 0, "Invalid price");

        uint256 addedSizeUsd = (additionalCollateral * additionalLeverage) / 1e6;

        require(collateralToken.transferFrom(msg.sender, address(this), additionalCollateral), "Transfer failed");
        collateralToken.approve(address(pool), additionalCollateral);
        pool.reserve(additionalCollateral);

        // Weighted average entry price
        uint256 newSize = p.size + addedSizeUsd;
        p.entryPrice = (p.entryPrice * p.size + price * addedSizeUsd) / newSize;

        p.size = newSize;
        p.collateral += additionalCollateral;

        emit PositionDecreased(msg.sender, addedSizeUsd, newSize, 0); // Optional
    }

    function addCollateral(uint256 amount) external {
        Position storage p = positions[msg.sender];
        require(p.size > 0, "No open position");

        require(collateralToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        collateralToken.approve(address(pool), amount);
        pool.reserve(amount);

        p.collateral += amount;
    }

    function decreasePosition(uint256 reduceSizeUsd) external {
        Position storage p = positions[msg.sender];
        require(p.size > 0, "No position");
        require(reduceSizeUsd > 0 && reduceSizeUsd <= p.size, "Invalid size");

        uint256 currentPrice = uint256(getLatestPrice());
        uint256 sizeClosed = reduceSizeUsd;
        uint256 collateralPortion = (p.collateral * sizeClosed) / p.size;

        int256 pnl;
        if (p.isLong) {
            pnl = int256(sizeClosed * currentPrice / p.entryPrice) - int256(sizeClosed);
        } else {
            pnl = int256(sizeClosed) - int256(sizeClosed * currentPrice / p.entryPrice);
        }

        int256 returnedCollateral = int256(collateralPortion) + pnl;
        require(returnedCollateral > 0, "Loss too large");

        p.size -= sizeClosed;
        p.collateral -= collateralPortion;

        pool.release(collateralPortion);
        collateralToken.transfer(msg.sender, uint256(returnedCollateral));

        if (p.size == 0) {
            delete positions[msg.sender];
            emit PositionClosed(msg.sender, uint256(returnedCollateral), pnl);
        } else {
            emit PositionDecreased(msg.sender, reduceSizeUsd, p.size, pnl);
        }
    }

    function closePosition() external {
        Position memory p = positions[msg.sender];
        require(p.size > 0, "No position");

        uint256 currentPrice = uint256(getLatestPrice());

        int256 pnl;
        if (p.isLong) {
            pnl = int256(p.size * currentPrice / p.entryPrice) - int256(p.size);
        } else {
            pnl = int256(p.size) - int256(p.size * currentPrice / p.entryPrice);
        }

        int256 finalCollateral = int256(p.collateral) + pnl;

        require(
            finalCollateral > 0 &&
            uint256(finalCollateral) * 1e6 / p.size >= minCollateralRatio,
            "Liquidated"
        );

        pool.release(p.collateral);
        delete positions[msg.sender];

        collateralToken.transfer(msg.sender, uint256(finalCollateral));

        emit PositionClosed(msg.sender, uint256(finalCollateral), pnl);
    }

    function getPnL(address user) external view returns (int256) {
        Position memory p = positions[user];
        if (p.size == 0) return 0;

        uint256 currentPrice = uint256(getLatestPrice());
        if (p.isLong) {
            return int256((p.size * currentPrice / p.entryPrice)) - int256(p.size);
        } else {
            return int256(p.size) - int256((p.size * currentPrice / p.entryPrice));
        }
    }
}
