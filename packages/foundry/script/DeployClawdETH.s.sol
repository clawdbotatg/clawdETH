// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeployHelpers.s.sol";
import "../contracts/ClawdETH.sol";

/**
 * @notice Deploy script for ClawdETH contract
 * @dev Deploys to Base mainnet with ether.fi weETH as the yield source.
 *
 * Addresses (Base mainnet):
 *   weETH:       0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A
 *   CLAWD:       0x9f86dB9fc6f7c9408e8Fda3Ff8ce4e78ac7a6b07
 *   WETH:        0x4200000000000000000000000000000000000006
 *   SwapRouter:  0x2626664c2603336E57B271c5C0b26F421741e481
 *
 * Usage:
 *   yarn deploy --file DeployClawdETH.s.sol                    # local anvil
 *   yarn deploy --file DeployClawdETH.s.sol --network base     # Base mainnet
 */
contract DeployClawdETH is ScaffoldETHDeploy {
    // ─── Base mainnet addresses ─────────────────────────────────────────
    address constant WEETH = 0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A;
    address constant CLAWD = 0x9f86dB9fc6f7c9408e8Fda3Ff8ce4e78ac7a6b07;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant SWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;

    function run() external ScaffoldEthDeployerRunner {
        ClawdETH clawdETH = new ClawdETH(WEETH, CLAWD, WETH, SWAP_ROUTER);

        console.log("ClawdETH deployed at:", address(clawdETH));
        console.log("  weETH:", address(clawdETH.weETH()));
        console.log("  CLAWD:", address(clawdETH.clawd()));
        console.log("  WETH:", address(clawdETH.weth()));
        console.log("  SwapRouter:", address(clawdETH.swapRouter()));
    }
}
