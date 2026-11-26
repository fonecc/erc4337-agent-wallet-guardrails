// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SessionWallet} from "../src/SessionWallet.sol";

interface Vm {
    function addr(uint256 key) external returns (address);
    function deal(address account, uint256 balance) external;
    function expectRevert(bytes4 selector) external;
    function prank(address caller) external;
    function sign(uint256 key, bytes32 digest) external returns (uint8, bytes32, bytes32);
    function warp(uint256 time) external;
}

contract SessionWalletTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address payable private constant RECIPIENT = payable(address(0xBEEF));
    uint256 private constant KEY = 1;
    SessionWallet private wallet;
    address private agent;
    uint256 private expiry;

    function setUp() public {
        wallet = new SessionWallet();
        vm.deal(address(wallet), 5 ether);
        agent = vm.addr(KEY);
        expiry = block.timestamp + 1 days;
        wallet.grant(agent, RECIPIENT, 1 ether, expiry);
    }

    function testPaymentConsumesBudget() public {
        uint256 beforeBalance = RECIPIENT.balance;
        pay(KEY, RECIPIENT, 0.4 ether, 0, bytes4(0));
        pay(KEY, RECIPIENT, 0.6 ether, 1, bytes4(0));
        require(RECIPIENT.balance == beforeBalance + 1 ether, "payment missing");
        pay(KEY, RECIPIENT, 1 wei, 2, SessionWallet.InvalidOperation.selector);
    }

    function testRejectsUnexpectedRecipient() public {
        pay(KEY, payable(address(0xCAFE)), 1 wei, 0, SessionWallet.InvalidOperation.selector);
    }

    function testRejectsWrongSigner() public {
        pay(2, RECIPIENT, 1 wei, 0, SessionWallet.InvalidOperation.selector);
    }

    function testRejectsReplay() public {
        pay(KEY, RECIPIENT, 1 wei, 0, bytes4(0));
        pay(KEY, RECIPIENT, 1 wei, 0, SessionWallet.InvalidOperation.selector);
    }

    function testRejectsAtExpiry() public {
        vm.warp(expiry);
        pay(KEY, RECIPIENT, 1 wei, 0, SessionWallet.InvalidOperation.selector);
    }

    function testRevocationInvalidatesPresignedPaymentAndRequiresNewKey() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(KEY, wallet.digest(agent, RECIPIENT, 1 wei, 0));
        wallet.revoke(agent);

        vm.expectRevert(SessionWallet.InvalidGrant.selector);
        wallet.grant(agent, RECIPIENT, 1 ether, expiry);
        address freshAgent = vm.addr(2);
        wallet.grant(freshAgent, RECIPIENT, 1 ether, expiry);

        vm.expectRevert(SessionWallet.InvalidOperation.selector);
        wallet.pay(agent, RECIPIENT, 1 wei, 0, v, r, s);

        agent = freshAgent;
        pay(2, RECIPIENT, 1 wei, 0, bytes4(0));
    }

    function testOnlyOwnerManagesSessions() public {
        address freshAgent = vm.addr(2);
        vm.prank(agent);
        vm.expectRevert(SessionWallet.Unauthorized.selector);
        wallet.grant(freshAgent, RECIPIENT, 1 ether, expiry);

        vm.prank(agent);
        vm.expectRevert(SessionWallet.Unauthorized.selector);
        wallet.revoke(agent);
    }

    function pay(uint256 key, address payable recipient, uint256 amount, uint256 nonce, bytes4 expectedError) private {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, wallet.digest(agent, recipient, amount, nonce));
        if (expectedError != bytes4(0)) vm.expectRevert(expectedError);
        wallet.pay(agent, recipient, amount, nonce, v, r, s);
    }
}
