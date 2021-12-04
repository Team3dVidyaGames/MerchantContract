// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IInventory.sol";
import "./interfaces/IGame.sol";


contract Merchant is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Event emitted only on construction.
    event MerchantDeployed();

    /// @notice Event emitted when inventory fee has updated.
    event InventoryFeeUpdated(uint256 newInventoryFee);

    /// @notice Event emitted when whitelist of game has updated.
    event WhitelistUpdated(address gameAddr, bool status);

    /// @notice Event emitted when profit has withdrawn.
    event ProfitWithdrew(uint256 profit);

    //System information
    IInventory public Inventory;
    IERC20 public Vidya;
    address public vaultAddr;

    //Listing Fee for devs
    uint256 public inventoryFee;

    struct ItemFeatures {
        uint8 feature1;
        uint8 feature2;
        uint8 feature3;
        uint8 feature4;
        uint8 equipmentPosition; 
    }

    struct Supplies{
        uint256 stock; // how many merchant has in stock right now
        uint256 stockCap; // the stock cap that restock fills up to
        uint256 restockTime; // time of last restock
        uint256 cooldownTime; // time left until next restock is possible (ie. an item has 1 day cooldownTime between restocks)
    }
    
    struct Item {
        address game; // which game is selling this
        uint256 templateId; // which item is this
        uint256 index;
        uint256 price; // the price of this item
        uint256 buyBackPrice; // what the merchant is willing to pay for this item
        Supplies wareHouse;
        ItemFeatures features;
        uint256 priceImpact;

    }

    // All Items being sold
    Item[] public allItems;

    // All Fees collected
    uint256 public collectedFees;

    // All buyBackPrice(s) ensures proper spending
    uint256 public buyBackPrices;

    // Get A item from _game by _templateId
    mapping(address => mapping(uint256 => Item)) public itemByGame;

    // Get all templateIds by _game
    mapping(address => uint256[]) public templateIdsByGame;

    // Get games by templateID
    mapping(uint256 => address[]) public gamesByTemplateId;

    // Games that are allowed to use merchant
    mapping(address => bool) public whitelist;

    // TemplatedId count per game. Needed by templateIdsByGame()
    mapping(address => uint256) public totalItemsForSaleByGame;

    modifier isDevOf(address _game) {
        require(
            msg.sender == devOf(_game),
            "Merchant: Caller is not the Game developer"
        );
        _;
    }

    /**
     * @dev Constructor function
     * @param _inventoryFee Inventory Fee
     * @param _Inventory Interface of Inventory
     * @param _Vidya Interface of Vidya
     * @param _vaultAddr Address of Vault
     */
    constructor(
        uint256 _inventoryFee,
        IInventory _Inventory,
        IERC20 _Vidya,
        address _vaultAddr
    ) {
        inventoryFee = _inventoryFee;
        Inventory = _Inventory;
        Vidya = _Vidya;
        vaultAddr = _vaultAddr;

        emit MerchantDeployed();
    }

    /**
     * @dev Public function to get the profits.
     */
    function profits() public view returns (uint256) {
        return Vidya.balanceOf(address(this)) - buyBackPrices;
    }

    /**
     * @dev Public function to get the game developer address.
     * @param _game Address of Game
     */
    function devOf(address _game) public view returns (address) {
        IGame game = IGame(_game);
        return game.developer();
    }

    /**
     * @dev Public function to get the game developer fee.
     * @param _game Address of Game
     */
    function devFee(address _game) public view returns (uint256) {
        IGame game = IGame(_game);
        return game.devFee();
    }

    /**
     * @dev Public function to return the total price of _templateId from _game a player is expected to pay.
     * @param _templateId Template Id
     * @param _game Address of Game
     */
    function sellPrice(uint256 _templateId, address _game)
        public
        view
        returns (uint256)
    {
        Item memory item = itemByGame[_game][_templateId];
        return item.price + devFee(_game);
    }

    /**
     * @dev Public function to get features and equipmentPosition of item by game. Help to prevent stack too deep error in sellTemplateId() function.
     * @param _game Address of Game
     * @param _templateId Template Id
     */
    function detailsOfItemByGame(address _game, uint256 _templateId)
        public
        view
        returns (uint8[5] memory features)
    {
        Item memory item = itemByGame[_game][_templateId];
        features[0] = item.features.feature1;
        features[1] = item.features.feature2;
        features[2] = item.features.feature3;
        features[3] = item.features.feature4;
        features[4] = item.features.equipmentPosition;
        return features;
    }

    /**
     * @dev Public function to sell item to player. (player is buying)
     * @param _templateId Template Id
     * @param _game Address of Game
     * @param _receiver Receiver address
     * @param _amount Item amount
     */
    function sellItem(
        uint256 _templateId,
        address _game,
        address _receiver,
        uint256 _amount
    ) public nonReentrant returns (uint256, bool) {
        restock(_game, _templateId);
        return sellTemplateId(_templateId, _game, _receiver, _amount);
    }

    /**
     * @dev Internal function to sell items by template id from game. (player is buying)
     * @param _templateId Template Id
     * @param _game Address of Game
     * @param _receiver Receiver address
     * @param _amount Item amount
     */
    function sellTemplateId(
        uint256 _templateId,
        address _game,
        address _receiver,
        uint256 _amount
    ) internal returns (uint256, bool) {
        Item storage item = itemByGame[_game][_templateId];
        require(item.wareHouse.stock >= _amount,
            "Merchant: Item requested is out of stock"
        );
        // Transfer buyBackPrice to Merchant contract
        Vidya.safeTransferFrom(msg.sender,address(this),item.buyBackPrice);
        // Transfer dev fee to game developer
        Vidya.safeTransferFrom(msg.sender, devOf(_game), devFee(_game));
        //Sends Profits to Vault
        Vidya.safeTransferFrom(msg.sender, vaultAddr, item.price - item.buyBackPrice);

        // Track the buyBackPrices
        buyBackPrices += item.buyBackPrice;

        item.price +=  (item.price * item.priceImpact * _amount) / 10000;
        item.wareHouse.stock -= _amount;

        // Materialize
        uint256 tokenId = Inventory.createItemFromTemplate(
            _templateId,
            item.features.feature1,
            item.features.feature2,
            item.features.feature3,
            item.features.feature4,
            item.features.equipmentPosition,
            _amount,
            _receiver
        );

        return (tokenId, true);
    }

    /**
     * @dev External function to buy a token back from the player (burns the token and sends buyBackPrice to player)
     * @param _tokenId Token Id
     * @param _game Address of Game
     * @param _holder Token holder address
     * @param _amount Item amount
     */
    function buyTokenId(
        uint256 _tokenId,
        address _game,
        address _holder,
        uint256 _amount
    ) external returns (uint256) {
        IInventory.Item memory inventoryItem = Inventory.allItems(_tokenId);

        uint256 templateId = inventoryItem.templateId;

        Item storage item = itemByGame[_game][templateId];

        Inventory.burn(_holder, _tokenId, _amount);
        item.wareHouse.stock += _amount;

        Vidya.safeTransfer(msg.sender, item.buyBackPrice);

        // Track the buyBackPrices
        buyBackPrices -= item.buyBackPrice;

        return templateId;
    }

    /**
     * @dev Internal function to restock item.
     * @param _game Address of Game
     * @param _templateId Template Id
     */
    function restock(address _game, uint256 _templateId) internal {
        Item storage item = itemByGame[_game][_templateId];
        
        if (block.timestamp - item.wareHouse.restockTime >= item.wareHouse.cooldownTime) {
            item.wareHouse.stock = item.wareHouse.stockCap;
            item.wareHouse.restockTime = block.timestamp;
        }

    }

    /**
     * @dev External function to update invetory fee. This function can be called only by owner.
     * @param _fee New inventory fee
     */
    function updateInventoryFee(uint256 _fee) external onlyOwner {
        inventoryFee = _fee;

        emit InventoryFeeUpdated(inventoryFee);
    }

    /**
     * @dev External function to update whitelist. This function can be called only by owner.
     * @param _game Address of game to approve
     * @param _status Game approval
     */
    function updateWhitelist(address _game, bool _status) external onlyOwner {
        whitelist[_game] = _status;

        emit WhitelistUpdated(_game, _status);
    }

    /**
     * @dev External function to withdraw the profit. This function can be called only by owner.
     */
    function withdrawProfit() external onlyOwner {
        uint256 profit = profits();
        Vidya.transfer(msg.sender, profit);

        emit ProfitWithdrew(profit);
    }

    /**
     * @dev External function to allow game developer can list new items on merchant. This function can be called only by game developer.
     * @param _game Address of game
     * @param _templateId Template id
     * @param _price Token price
     * @param _buyBackPrice Price that merchant is willing to pay for item
     * @param stock Supplies Information
     * @param _details Item features
     * @param _priceImpact Price impact adjust the price every buy. For no impact enter 0.
     */
    function listNewItem(
        address _game,
        uint256 _templateId,
        uint256 _price,
        uint256 _buyBackPrice,
        Supplies memory stock,
        ItemFeatures memory _details,
        uint256 _priceImpact

    ) external isDevOf(_game) {
        require(
            _buyBackPrice < _price,
            "Merchant: Buyback price cannot be bigger than item price"
        ); // this would be very bad if allowed!

        require(whitelist[_game], "Merchant: Game is not whitelisted");

        // Fails when totalSupply of template is 0. Not added by admin to inventory contract
        require(
            Inventory.templateExists(_templateId),
            "Merchant: Trying to add item that does not exist yet"
        );

        require(
            Inventory.templateApprovedGames(_templateId, _game),
            "Merchant: Game is not approved"
        );

        Item memory item;
        stock.restockTime = block.timestamp;

        if (gamesByTemplateId[_templateId].length > 0) {
            address game = gamesByTemplateId[_templateId][0];
            item = itemByGame[game][ _templateId];
        } else {
            item = Item(
                _game,
                _templateId,
                0,
                _price,
                _buyBackPrice,
                stock,
                _details,
                _priceImpact
            );
        }
        // Transfer the listing fee to owner
        Vidya.safeTransferFrom(msg.sender, owner(), inventoryFee);

        // Update fees-to-inventory tracker
        collectedFees += inventoryFee;

        totalItemsForSaleByGame[_game]++;
        uint256 index = allItems.length;
        itemByGame[_game][_templateId] = Item(
            _game,
            _templateId,
            index,
            item.price,
            item.buyBackPrice,
            stock,
            _details,
            item.priceImpact
        );

        allItems.push(
            Item(
                _game,
                _templateId,
                index,
                item.price,
                item.buyBackPrice,
                stock,
                _details,
                item.priceImpact
            )
        );
        gamesByTemplateId[_templateId].push(_game);
        templateIdsByGame[_game].push(_templateId);
    }
}
