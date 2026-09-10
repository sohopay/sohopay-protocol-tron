// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {MockERC20} from "./MockERC20.sol";

/// @notice Standard 6-decimal USDC mock for local Foundry / A2A demo tests.
///         Not a non-standard USDT stand-in — transfers return bool.
contract MockUSDC is MockERC20 {
    constructor() MockERC20("USD Coin", "USDC", 6) {}
}
