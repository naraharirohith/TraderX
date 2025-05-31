// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IPerpMarket {
    function openPosition(uint256 collateralAmount, uint256 leverage, bool isLong) external;
    function closePosition() external;
    function increasePosition(uint256 collateralAmount, uint256 leverage) external;
    function decreasePosition(uint256 reduceSizeUsd) external;
}

interface ICCIPRouter {
    function ccipReceive(bytes calldata message) external;
}

contract VaultReceiver {
    address public immutable router;
    address public immutable sourceSender;
    IPerpMarket public perpMarket;

    event IntentReceived(address indexed user, uint8 action);

    constructor(address _router, address _sourceSender, address _perpMarket) {
        router = _router;
        sourceSender = _sourceSender;
        perpMarket = IPerpMarket(_perpMarket);
    }

    modifier onlyRouter() {
        require(msg.sender == router, "Not router");
        _;
    }

    // Called by Chainlink CCIP
    function ccipReceive(bytes calldata data) external onlyRouter {
        // Decode message
        (address user, uint8 action, uint256 collateral, uint256 leverage, bool isLong) =
            abi.decode(data, (address, uint8, uint256, uint256, bool));

        require(tx.origin == router, "Unauthorized origin"); // Optional for replay protection

        emit IntentReceived(user, action);

        // Execute intent using delegate pattern
        if (action == 0) {
            _delegateCall(user, abi.encodeWithSelector(
                perpMarket.openPosition.selector, collateral, leverage, isLong
            ));
        } else if (action == 1) {
            _delegateCall(user, abi.encodeWithSelector(
                perpMarket.closePosition.selector
            ));
        } else if (action == 2) {
            _delegateCall(user, abi.encodeWithSelector(
                perpMarket.increasePosition.selector, collateral, leverage
            ));
        } else if (action == 3) {
            _delegateCall(user, abi.encodeWithSelector(
                perpMarket.decreasePosition.selector, collateral
            ));
        } else {
            revert("Unknown action");
        }
    }

    function _delegateCall(address user, bytes memory data) internal {
        (bool success, ) = address(perpMarket).call(abi.encodePacked(data, user));
        require(success, "Delegate call failed");
    }
}
