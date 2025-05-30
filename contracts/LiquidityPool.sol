// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title LPToken - ERC20 token representing liquidity shares
contract LPToken is ERC20, Ownable {
    constructor() ERC20("XCV LP Token", "XCV-LP") Ownable(msg.sender) {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

/// @title LiquidityPool - Handles LP deposits/withdrawals
contract LiquidityPool {
    IERC20 public collateralToken;
    LPToken public lpToken;
    address public market;

    uint256 public totalLiquidity;
    uint256 public reservedLiquidity;
    uint256 public totalCollateralDeposited;
    uint256 public totalCollateralWithdrawn;

    event Deposit(address indexed user, uint256 amount, uint256 sharesMinted);
    event Withdraw(address indexed user, uint256 sharesBurned, uint256 amount);
    event Reserve(address indexed market, uint256 amount);
    event Release(address indexed market, uint256 amount);

    constructor(address _collateralToken) {
        collateralToken = IERC20(_collateralToken);
        lpToken = new LPToken();
    }

    modifier onlyMarket() {
        require(msg.sender == market, "Only market");
        _;
    }

    function setMarket(address _market) external {
        require(market == address(0), "Already set");
        market = _market;
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "Zero amount");
        require(collateralToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        uint256 shares = (totalLiquidity == 0 || lpToken.totalSupply() == 0)
            ? amount
            : (amount * lpToken.totalSupply()) / totalLiquidity;

        lpToken.mint(msg.sender, shares);
        totalLiquidity += amount;
        totalCollateralDeposited += amount;

        emit Deposit(msg.sender, amount, shares);
    }

    function withdraw(uint256 shares) external {
        require(shares > 0, "Zero shares");
        require(lpToken.balanceOf(msg.sender) >= shares, "Insufficient shares");

        uint256 amount = (shares * totalLiquidity) / lpToken.totalSupply();
        require(amount <= (totalLiquidity - reservedLiquidity), "Insufficient free liquidity");

        lpToken.burn(msg.sender, shares);
        totalLiquidity -= amount;
        totalCollateralWithdrawn += amount;

        require(collateralToken.transfer(msg.sender, amount), "Transfer failed");

        emit Withdraw(msg.sender, shares, amount);
    }

    function reserve(uint256 amount) external onlyMarket {
        require(totalLiquidity - reservedLiquidity >= amount, "Insufficient available liquidity");
        reservedLiquidity += amount;

        emit Reserve(msg.sender, amount);
    }

    function release(uint256 amount) external onlyMarket {
        require(reservedLiquidity >= amount, "Not reserved");
        reservedLiquidity -= amount;

        emit Release(msg.sender, amount);
    }

    function availableLiquidity() external view returns (uint256) {
        return totalLiquidity - reservedLiquidity;
    }
}
