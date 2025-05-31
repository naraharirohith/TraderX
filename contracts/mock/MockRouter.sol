// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IVaultReceiver {
    function ccipReceive(bytes calldata data) external;
}

contract MockRouter {
    address public vaultReceiver;

    constructor(address _vaultReceiver) {
        vaultReceiver = _vaultReceiver;
    }

    function ccipSend(
        uint64 /* destinationChainSelector */,
        address /* receiver */,
        bytes calldata data
    ) external returns (bytes32) {
        IVaultReceiver(vaultReceiver).ccipReceive(data);
        return keccak256(data); // Simulate messageId
    }
}
