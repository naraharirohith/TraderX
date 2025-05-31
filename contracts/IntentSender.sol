// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ICCIPRouter {
    function ccipSend(
        uint64 destinationChainSelector,
        address receiver,
        bytes calldata data
    ) external payable returns (bytes32);

    function ccipReceive(bytes calldata data) external;
}

contract IntentSender {
    ICCIPRouter public router;
    uint64 public vaultChainSelector;
    address public vaultReceiver; // VaultReceiver address on Vault Chain

    event MessageSent(address indexed user, uint8 action, bytes32 messageId);

    constructor(address _router, uint64 _vaultChainSelector, address _vaultReceiver) {
        router = ICCIPRouter(_router);
        vaultChainSelector = _vaultChainSelector;
        vaultReceiver = _vaultReceiver;
    }

    function sendOpenPosition(uint256 collateral, uint256 leverage, bool isLong) external {
        bytes memory payload = abi.encode(
            msg.sender,
            uint8(0), // action = OPEN
            collateral,
            leverage,
            isLong
        );

        bytes32 messageId = router.ccipSend(
            vaultChainSelector,
            vaultReceiver,
            payload
        );

        emit MessageSent(msg.sender, 0, messageId);
    }

    function sendClosePosition() external {
        bytes memory payload = abi.encode(
            msg.sender,
            uint8(1), // action = CLOSE
            0,
            0,
            false
        );

        bytes32 messageId = router.ccipSend(
            vaultChainSelector,
            vaultReceiver,
            payload
        );

        emit MessageSent(msg.sender, 1, messageId);
    }

    function sendIncreasePosition(uint256 collateral, uint256 leverage) external {
        bytes memory payload = abi.encode(
            msg.sender,
            uint8(2), // action = INCREASE
            collateral,
            leverage,
            false
        );

        bytes32 messageId = router.ccipSend(
            vaultChainSelector,
            vaultReceiver,
            payload
        );

        emit MessageSent(msg.sender, 2, messageId);
    }

    function sendDecreasePosition(uint256 reduceSizeUsd) external {
        bytes memory payload = abi.encode(
            msg.sender,
            uint8(3), // action = DECREASE
            reduceSizeUsd,
            0,
            false
        );

        bytes32 messageId = router.ccipSend(
            vaultChainSelector,
            vaultReceiver,
            payload
        );

        emit MessageSent(msg.sender, 3, messageId);
    }
}
