// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

/**
 * @title Inventory Interface
 */
interface IGame {
    /**
     * @dev External function to get the game developer address.
     */
    function developer() external view returns (address);

    /**
     * @dev External function to get the dev fee.
     */
    function devFee() external view returns (uint256);
}
