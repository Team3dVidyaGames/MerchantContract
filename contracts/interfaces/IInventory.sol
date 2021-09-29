// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

/**
 * @title Inventory Interface
 */
interface IInventory {
    /**
     * @dev External function to create item from templates. This function can be called by approved games only.
     * @param _templateId Id of template
     * @param _feature1 Feature 1
     * @param _feature2 Feature 2
     * @param _feature3 Feature 3
     * @param _feature4 Feature 4
     * @param _equipmentPosition Equipment position
     * @param _amount Amount of Item
     * @param _player Address of player
     * @return Token Id
     */
    function createItemFromTemplate(
        uint256 _templateId,
        uint8 _feature1,
        uint8 _feature2,
        uint8 _feature3,
        uint8 _feature4,
        uint8 _equipmentPosition,
        uint256 _amount,
        address _player
    ) external returns (uint256);

    /**
     * @dev External function to burn the token.
     * @param _owner Address of token owner
     * @param _tokenId Token id
     * @param _amount Token amount
     */
    function burn(
        address _owner,
        uint256 _tokenId,
        uint256 _amount
    ) external;

    /**
     * @dev External function to mint the token.
     * @param _user Address of user
     * @param _tokenId Token id
     * @param _amount Token amount
     */
    function mint(
        address _user,
        uint256 _tokenId,
        uint256 _amount
    ) external;
}
