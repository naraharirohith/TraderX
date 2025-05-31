// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./LiquidityPool.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

interface IPriceFeed {
    function getPrice() external view returns (uint256);
}

contract PerpMarket {
    AggregatorV3Interface internal priceFeed;

    struct Position {
        uint256 size;
        uint256 entryPrice;
        uint256 collateral;
        bool isLong;
        uint256 lastFundingTime;
    }

    mapping(address => Position) public positions;
    LiquidityPool public pool;
    IERC20 public collateralToken;

    uint256 public minCollateralRatio = 1000; // 10% in basis points
    uint256 public fundingRate = 50; // 0.005% per hour
    uint256 public maxUtilizationRatio = 8000; // 80%

    event PositionOpened(address indexed user, uint256 size, uint256 collateral, uint256 entryPrice, bool isLong);
    event PositionClosed(address indexed user, uint256 finalCollateral, int256 pnl);
    event PositionDecreased(address indexed user, uint256 reducedSize, uint256 remainingSize, int256 pnl);
    event PositionLiquidated(address indexed user, uint256 penalty);
    event LiquidatedBy(address indexed liquidator, address indexed user, uint256 reward);

    constructor(address _pool, address _priceFeed) {
        pool = LiquidityPool(_pool);
        collateralToken = IERC20(pool.collateralToken());
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    function getLatestPrice() public view returns (int256) {
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return price;
    }

    function _validateUtilization(uint256 sizeUsd) internal view {
        uint256 total = pool.totalLiquidity();
        uint256 reserved = pool.reservedLiquidity();
        require(total > 0, "Empty pool");

        uint256 utilization = ((reserved + sizeUsd) * 10000) / total;
        require(utilization <= maxUtilizationRatio, "Exceeds utilization limit");
    }

    function _applyFunding(address user) internal {
        Position storage p = positions[user];
        if (p.size == 0) return;

        uint256 timeElapsed = block.timestamp - p.lastFundingTime;
        if (timeElapsed == 0) return;

        int256 fundingFee = int256(p.size) * int256(fundingRate) * int256(timeElapsed) / int256(1e6 * 3600);
        if (p.isLong) {
            p.collateral -= uint256(fundingFee);
        } else {
            p.collateral += uint256(fundingFee);
        }

        p.lastFundingTime = block.timestamp;
    }

    function _isLiquidatable(Position memory p) internal view returns (bool) {
        uint256 currentPrice = uint256(getLatestPrice());
        int256 pnl = p.isLong
            ? int256(p.size * currentPrice / p.entryPrice) - int256(p.size)
            : int256(p.size) - int256(p.size * currentPrice / p.entryPrice);

        int256 finalCollateral = int256(p.collateral) + pnl;
        if (finalCollateral <= 0) return true;

        uint256 collateralRatioBps = (uint256(finalCollateral) * 1e6 * 10000) / p.size;
        return collateralRatioBps < minCollateralRatio;
    }

    function liquidate(address user) external {
        _applyFunding(user);
        Position memory p = positions[user];
        require(p.size > 0, "No position");
        require(_isLiquidatable(p), "Not liquidatable");

        uint256 penalty = (p.collateral * 5) / 100;
        uint256 reward = penalty / 2;

        uint256 collateralToRelease = p.collateral > pool.reservedLiquidity() ? pool.reservedLiquidity() : p.collateral;
        pool.release(collateralToRelease);

        collateralToken.transfer(msg.sender, reward);
        collateralToken.transfer(address(pool), penalty - reward);

        emit PositionLiquidated(user, penalty);
        emit LiquidatedBy(msg.sender, user, reward);
        delete positions[user];
    }

    function openPosition(uint256 collateralAmount, uint256 leverage, bool isLong) external {
        require(positions[msg.sender].size == 0, "Position already open");
        require(collateralAmount > 0, "Zero collateral");
        require(leverage >= 1e6 && leverage <= 10e6, "1x to 10x");

        uint256 price = uint256(getLatestPrice());
        require(price > 0, "Invalid price");

        uint256 sizeUsd = (collateralAmount * leverage) / 1e6;
        _validateUtilization(sizeUsd);

        require(collateralToken.transferFrom(msg.sender, address(this), collateralAmount), "Transfer failed");
        collateralToken.approve(address(pool), collateralAmount);
        pool.reserve(collateralAmount);

        positions[msg.sender] = Position({
            size: sizeUsd,
            entryPrice: price,
            collateral: collateralAmount,
            isLong: isLong,
            lastFundingTime: block.timestamp
        });

        emit PositionOpened(msg.sender, sizeUsd, collateralAmount, price, isLong);
    }

    function increasePosition(uint256 additionalCollateral, uint256 additionalLeverage) external {
        _applyFunding(msg.sender);
        Position storage p = positions[msg.sender];
        require(p.size > 0, "No existing position");
        require(additionalCollateral > 0, "Zero collateral");
        require(additionalLeverage >= 1e6 && additionalLeverage <= 10e6, "Invalid leverage");

        uint256 price = uint256(getLatestPrice());
        require(price > 0, "Invalid price");

        uint256 addedSizeUsd = (additionalCollateral * additionalLeverage) / 1e6;
        _validateUtilization(addedSizeUsd);

        require(collateralToken.transferFrom(msg.sender, address(this), additionalCollateral), "Transfer failed");
        collateralToken.approve(address(pool), additionalCollateral);
        pool.reserve(additionalCollateral);

        uint256 newSize = p.size + addedSizeUsd;
        p.entryPrice = (p.entryPrice * p.size + price * addedSizeUsd) / newSize;

        p.size = newSize;
        p.collateral += additionalCollateral;

        emit PositionDecreased(msg.sender, addedSizeUsd, newSize, 0);
    }

    function addCollateral(uint256 amount) external {
        _applyFunding(msg.sender);
        Position storage p = positions[msg.sender];
        require(p.size > 0, "No open position");

        require(collateralToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        collateralToken.approve(address(pool), amount);
        pool.reserve(amount);

        p.collateral += amount;
    }

    function decreasePosition(uint256 reduceSizeUsd) external {
        _applyFunding(msg.sender);
        Position storage p = positions[msg.sender];
        require(p.size > 0, "No position");
        require(reduceSizeUsd > 0 && reduceSizeUsd <= p.size, "Invalid size");

        uint256 currentPrice = uint256(getLatestPrice());
        uint256 sizeClosed = reduceSizeUsd;
        uint256 collateralPortion = (p.collateral * sizeClosed) / p.size;

        int256 pnl = p.isLong
            ? int256(sizeClosed * currentPrice / p.entryPrice) - int256(sizeClosed)
            : int256(sizeClosed) - int256(sizeClosed * currentPrice / p.entryPrice);

        int256 returnedCollateral = int256(collateralPortion) + pnl;
        require(returnedCollateral > 0, "Loss too large");

        p.size -= sizeClosed;
        p.collateral -= collateralPortion;

        uint256 collateralToRelease = collateralPortion > pool.reservedLiquidity() ? pool.reservedLiquidity() : collateralPortion;
        pool.release(collateralToRelease);
        collateralToken.transfer(msg.sender, uint256(returnedCollateral));

        if (p.size == 0) {
            delete positions[msg.sender];
            emit PositionClosed(msg.sender, uint256(returnedCollateral), pnl);
        } else {
            emit PositionDecreased(msg.sender, reduceSizeUsd, p.size, pnl);
        }
    }

    function closePosition() external {
        _applyFunding(msg.sender);
        Position memory p = positions[msg.sender];
        require(p.size > 0, "No position");

        uint256 currentPrice = uint256(getLatestPrice());
        require(currentPrice > 0, "Invalid price");

        int256 pnl = p.isLong
            ? int256(p.size * currentPrice / p.entryPrice) - int256(p.size)
            : int256(p.size) - int256(p.size * currentPrice / p.entryPrice);

        int256 finalCollateral = int256(p.collateral) + pnl;

        uint256 collateralToRelease = p.collateral > pool.reservedLiquidity() ? pool.reservedLiquidity() : p.collateral;

        if (finalCollateral <= 0) {
            uint256 penalty = (p.collateral * 5) / 100;
            pool.release(collateralToRelease);
            collateralToken.transfer(address(pool), penalty / 2);
            emit PositionLiquidated(msg.sender, penalty);
            delete positions[msg.sender];
            return;
        }

        uint256 collateralRatioBps = (uint256(finalCollateral) * 1e6 * 10000) / p.size;

        if (collateralRatioBps < minCollateralRatio) {
            uint256 penalty = (p.collateral * 5) / 100;
            pool.release(collateralToRelease);
            collateralToken.transfer(address(pool), penalty / 2);
            emit PositionLiquidated(msg.sender, penalty);
            delete positions[msg.sender];
            return;
        }

        pool.release(collateralToRelease);
        delete positions[msg.sender];
        collateralToken.transfer(msg.sender, uint256(finalCollateral));

        emit PositionClosed(msg.sender, uint256(finalCollateral), pnl);
    }

    function getPnL(address user) external view returns (int256) {
        Position memory p = positions[user];
        if (p.size == 0) return 0;

        uint256 currentPrice = uint256(getLatestPrice());
        return p.isLong
            ? int256((p.size * currentPrice / p.entryPrice)) - int256(p.size)
            : int256(p.size) - int256((p.size * currentPrice / p.entryPrice));
    }
}
