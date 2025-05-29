// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract MockPriceFeed {
    uint256 public price = 2000 * 1e8;

    function setPrice(uint256 _price) external {
        price = _price;
    }

    function getPrice() external view returns (uint256) {
        return price;
    }

    function latestRoundData() public view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (uint80(0), int256(price), 0, 0, uint80(0));
    }
}
