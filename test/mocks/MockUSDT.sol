// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title  MockUSDT — 6-decimal mintable ERC-20 for the Plasma testnet demo
/// @notice Stand-in for USDT0 on Plasma testnet, where no public USDT0 exists. Mainnet USDT0
///         (0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb) is 6-decimal; this matches so the
///         DeployConfig amount math ($100 == 100e6) is unchanged. Open `mint` — demo only.
contract MockUSDT is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
