// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./interfaces/IInventory.sol";

contract Merchant is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Strings for uint256;

    IInventory Inventory;
    IERC20 Vidya;

    // Item
    struct Item {
        address game; // which game is selling this
        uint256 templateId; // which item is this
        uint256 price; // the price of this item
        uint256 buyBackPrice; // what the merchant is willing to pay for this item
        uint256 stock; // how many merchant has in stock right now
        uint256 stockCap; // the stock cap that restock fills up to
        uint32 restockTime; // time of last restock
        uint32 cooldownTime; // time left until next restock is possible (ie. an item has 1 day cooldownTime between restocks)
        uint8 feature1;
        uint8 feature2;
        uint8 feature3;
        uint8 feature4;
        uint8 equipmentPosition;
    }

    // All Items being sold by merchant
    Item[] public allItems;

    // The Inventory contract's share (listing fee for devs)
    uint256 public inventoryFee;

    // All inventoryFee(s)
    uint256 public collectedFees;

    // All buyBackPrice(s) so we don't accidentally use these, ever.
    uint256 public buyBackPrices;

    // Games that are allowed to use merchant's services
    // This is for game devs and who can add or edit items etc.
    mapping(address => bool) public whitelist;

    // TemplateId count per game. Needed by templateIdsByGame()
    mapping(address => uint256) public totalItemsForSaleByGame;

    modifier isDevOf(address _game) {
        require(
            msg.sender == devOf(_game),
            "Merchant: Caller is not the Game developer"
        );
        _;
    }

    modifier inStock(address _game, uint256 _templateId) {
        (, , , , , uint256 stock, , , , , , , ) = itemByGame(
            _game,
            _templateId
        );
        require(stock > 0, "Merchant: Item requested is out of stock");
        _;
    }

    constructor(
        uint256 _inventoryFee,
        IInventory _Inventory,
        IERC20 _Vidya
    ) {
        inventoryFee = _inventoryFee;
        Inventory = _Inventory;
        Vidya = _Vidya;
    }

    // Function to return the Merchant's profit
    function profits() public view returns (uint256) {
        return Vidya.balanceOf(address(this)) - buyBackPrices;
    }

    // Function to return the dev of _game
    function devOf(address _game) public view returns (address) {
        iGame game = iGame(_game);
        return game.developer();
    }

    // Function to return the devFee of _game
    function devFee(address _game) public view returns (uint256) {
        iGame game = iGame(_game);
        return game.devFee();
    }

    // Function to return the total price of _templateId from _game a player is expected to pay
    function sellPrice(uint256 _templateId, address _game)
        public
        view
        returns (uint256)
    {
        (, , , uint256 price, , , , , , , , , ) = itemByGame(
            _game,
            _templateId
        );
        // item price + devfee
        // does not include inventory fee because this is for the dev to pay upon listing new items
        return price + devFee(_game);
    }

    // Get A item from _game by _templateId
    function itemByGame(address _game, uint256 _templateId)
        public
        view
        returns (
            address,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint32,
            uint32,
            uint8,
            uint8,
            uint8,
            uint8,
            uint8
        )
    {
        for (uint256 i = 0; i < allItems.length; i++) {
            if (
                allItems[i].game == _game &&
                allItems[i].templateId == _templateId
            ) {
                return (
                    allItems[i].game,
                    i, // the index in allItems array
                    allItems[i].templateId,
                    allItems[i].price,
                    allItems[i].buyBackPrice,
                    allItems[i].stock,
                    allItems[i].restockTime,
                    allItems[i].cooldownTime,
                    allItems[i].feature1,
                    allItems[i].feature2,
                    allItems[i].feature3,
                    allItems[i].feature4,
                    allItems[i].equipmentPosition
                );
            }
        }
    }

    // Get all templateIds by _game as an uint256 array
    function templateIdsByGame(address _game)
        public
        view
        returns (uint256[] memory)
    {
        uint256[] memory templateIds = new uint256[](
            totalItemsForSaleByGame[_game]
        );
        for (uint256 i = 0; i < allItems.length; i++) {
            if (allItems[i].game == _game) {
                templateIds[i] = allItems[i].templateId;
            }
        }
        return templateIds;
    }

    // Get features and equipmentPosition of item by game
    // Helps prevent stack too deep error in sellTemplateId() function
    function detailsOfItemByGame(address _game, uint256 _templateId)
        public
        view
        returns (uint8[] memory)
    {
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint8 feature1,
            uint8 feature2,
            uint8 feature3,
            uint8 feature4,
            uint8 equipmentPosition
        ) = itemByGame(_game, _templateId);
        uint8[] memory details = new uint8[](5);
        details[0] = feature1;
        details[1] = feature2;
        details[2] = feature3;
        details[3] = feature4;
        details[4] = equipmentPosition;
        return details;
    }

    // Public function to sell item to player (player is buying)
    function sellItem(uint256 _templateId, address _game)
        public
        returns (uint256, bool)
    {
        restock(_game, _templateId);
        return sellTemplateId(_templateId, _game);
    }

    // Sells a _templateId from _game (player is buying)
    function sellTemplateId(uint256 _templateId, address _game)
        internal
        inStock(_game, _templateId)
        returns (uint256, bool)
    {
        (
            ,
            ,
            ,
            uint256 price,
            uint256 buyBackPrice,
            ,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = itemByGame(_game, _templateId);
        uint8[] memory details = new uint8[](5);
        details = detailsOfItemByGame(_game, _templateId);

        // Transfer price to Merchant contract
        Vidya.safeTransferFrom(msg.sender, address(this), price);

        // Transfer dev fee to game developer
        Vidya.safeTransferFrom(msg.sender, devOf(_game), devFee(_game));

        // Track the buyBackPrices
        buyBackPrices = buyBackPrice + buyBackPrices;

        // Materialize
        uint256 tokenId = Inventory.createFromTemplate(
            _templateId,
            details[0],
            details[1],
            details[2],
            details[3],
            details[4]
        );

        // tokenId of the item sold to player
        return (tokenId, true);
    }

    // Sells multiple items of the same _templateId by _game
    function sellBulkTemplateId(
        address _game,
        uint256 _templateId,
        uint256 _amount
    ) public {
        for (uint256 i = 0; i < _amount; i++) {
            sellItem(_templateId, _game);
        }
    }

    // "buys" a token back from the player (burns the token and sends buyBackPrice to player)
    function buyTokenId(uint256 _tokenId, address _game)
        public
        returns (uint256)
    {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = _tokenId;
        uint256[] memory templateIds = new uint256[](1);
        templateIds = Inventory.getTemplateIDsByTokenIDs(tokenIds);
        uint256 templateId = templateIds[0];
        (, , , , uint256 buyBackPrice, , , , , , , , ) = itemByGame(
            _game,
            templateId
        );
        require(Inventory.burn(_tokenId), "Merchant: Token burn failed");
        Vidya.safeTransfer(msg.sender, buyBackPrice);

        // Track the buyBackPrices
        buyBackPrices = SafeMath.sub(buyBackPrices, buyBackPrice);

        return templateId;
    }

    // Restocks an item
    function restock(address _game, uint256 _templateId) internal {
        (
            ,
            uint256 index,
            ,
            ,
            ,
            ,
            uint32 restockTime,
            uint32 cooldownTime,
            ,
            ,
            ,
            ,

        ) = itemByGame(_game, _templateId);
        if (now - restockTime >= cooldownTime) {
            // Restock the item
            allItems[index].stock = allItems[index].stockCap;
            allItems[index].restockTime = uint32(now);
        }
    }

    /* ADMIN FUNCTIONS */

    function updateInventoryFee(uint256 _fee) external onlyOwner {
        inventoryFee = _fee;
    }

    function updateWhitelist(address _game, bool _status) external onlyOwner {
        whitelist[_game] = _status;
    }

    function withdrawProfit() external onlyOwner {
        uint256 profit = profits();
        // Send the tokens
        token.transfer(_admin, profit);
    }

    // Game developer can list new items on merchant
    function listNewItem(
        address _game,
        uint256 _templateId,
        uint256 _price,
        uint256 _buyBackPrice,
        uint256 _stock,
        uint256 _stockCap,
        uint32 _cooldownTime,
        uint8[] calldata _details
    ) external isDevOf(_game) {
        require(
            _buyBackPrice <= _price,
            "Merchant: Buyback price cannot be bigger than item price"
        ); // this would be very bad if allowed!
        require(whitelist[_game], "Merchant: Game is not whitelisted");

        uint256 totalSupply = Inventory.getIndividualCount(_templateId);

        // Fails when totalSupply of template is 0. Not added by admin to inventory contract
        require(
            totalSupply > 0,
            "Merchant: Trying to add item that does not exist yet"
        );

        // Transfer the listing fee to Inventory
        Vidya.safeTransferFrom(msg.sender, inventory, inventoryFee);

        // Update fees-to-inventory tracker
        collectedFees = inventoryFee + collectedFees;

        totalItemsForSaleByGame[_game]++;

        allItems.push(
            Item(
                _game,
                _templateId,
                _price,
                _buyBackPrice,
                _stock,
                _stockCap,
                uint32(now),
                _cooldownTime,
                _details[0], // feature1
                _details[1], // feature2
                _details[2], // feature3
                _details[3], // feature4
                _details[4] // equipmentPosition
            )
        );
    }
}
