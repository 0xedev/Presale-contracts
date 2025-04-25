// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Presale} from "src/contracts/Presale.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Simple contract to test reentrancy on contribute
contract MaliciousReentrantContributor {
    Presale public immutable presale;
    uint256 public callCount = 0;
    bytes32[] public proof; // Store proof if needed

    constructor(address _presale) {
        presale = Presale(payable(_presale));
    }

    function setProof(bytes32[] calldata _proof) external {
        proof = _proof;
    }

    function attackContribute() external payable {
        presale.contribute{value: msg.value}(proof);
    }

    // This will be called during the ETH transfer (if any happened, which it doesn't in contribute)
    // More relevantly, if contribute *did* send ETH back on some path, this could re-enter.
    // Or, if the token had a callback. Since neither is true, we rely on the nonReentrant modifier itself.
    // For claim, a malicious token could re-enter.
    receive() external payable {
        callCount++;
        if (callCount < 2) {
            // Attempt to re-enter contribute (will fail due to nonReentrant)
            // Note: This specific re-entry path might not be triggered depending
            // on Presale's logic, but tests the guard.
            try presale.contribute{value: 0.01 ether}(proof) {} catch {}
        }
    }
}

// Simple contract to test reentrancy on claim
contract MaliciousReentrantClaimer {
    Presale public immutable presale;
    IERC20 public immutable token;
    uint256 public callCount = 0;

    constructor(address _presale, address _token) {
        presale = Presale(payable(_presale));
        token = IERC20(_token);
    }

    function attackClaim() external {
        callCount = 0; // Reset count for each attack attempt
        presale.claim();
    }

    // This mock function simulates a callback during token transfer (like ERC777)
    // Standard ERC20 transfer doesn't call the recipient, so this simulates a potential vulnerability path.
    function onTokenTransfer() external {
        callCount++;
        if (callCount < 2) {
            // Attempt to re-enter claim (should fail due to nonReentrant)
            try presale.claim() {} catch {}
        }
    }
}
