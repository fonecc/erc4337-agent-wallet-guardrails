// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Teaching example for native ETH payments, not an ERC-4337 account.
contract SessionWallet {
    error Unauthorized();
    error InvalidGrant();
    error InvalidOperation();
    error PaymentFailed();

    struct Session {
        address payable recipient;
        uint256 remaining;
        uint256 expiry;
        uint256 nonce;
        bool revoked;
    }

    address public immutable owner = msg.sender;
    mapping(address => Session) public sessions;

    receive() external payable {}

    function grant(address agent, address payable recipient, uint256 cap, uint256 expiry) external {
        if (msg.sender != owner) revert Unauthorized();
        if (
            agent == address(0) || agent == owner || recipient == address(0) || cap == 0 || expiry <= block.timestamp
                || sessions[agent].expiry != 0
        ) revert InvalidGrant();
        sessions[agent] = Session(recipient, cap, expiry, 0, false);
    }

    function revoke(address agent) external {
        if (msg.sender != owner) revert Unauthorized();
        if (sessions[agent].expiry == 0) revert InvalidGrant();
        sessions[agent].revoked = true;
    }

    function digest(address agent, address recipient, uint256 amount, uint256 nonce) public view returns (bytes32) {
        bytes32 hash = keccak256(abi.encode(block.chainid, address(this), agent, recipient, amount, nonce));
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    function pay(address agent, address payable recipient, uint256 amount, uint256 nonce, uint8 v, bytes32 r, bytes32 s)
        external
    {
        Session storage session = sessions[agent];
        if (
            agent == address(0) || session.revoked || block.timestamp >= session.expiry
                || recipient != session.recipient || amount == 0 || amount > session.remaining || nonce != session.nonce
                || ecrecover(digest(agent, recipient, amount, nonce), v, r, s) != agent
        ) revert InvalidOperation();

        // Consume allowance and nonce before calling the recipient.
        session.remaining -= amount;
        ++session.nonce;
        (bool ok,) = recipient.call{value: amount}("");
        if (!ok) revert PaymentFailed();
    }
}
