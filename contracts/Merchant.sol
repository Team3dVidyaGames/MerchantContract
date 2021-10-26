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

    //System information
    IInventory public Inventory;
    IERC20 public Vidya;
    address public vault;
    //Listing Fee for devs
    uint256 public inventoryFee;


    struct Items {

        address game; // which game is selling this
        uint256 templateId; // which item is this
        uint256 index;

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
        uint8 priceSystem;
        uint256 rate;

    }

    // All Items being sold
    Items[] public allItems;

    // Get A item from _game by _templateId
    mapping(address => mapping(uint256 => Items)) public itemByGame;

    //Get all templateIds by _game
    mapping(address=> uint256[]) public templateIdsByGame;

    //Get games by templateID
    mapping(uint256 => address[]) public gamesByTemplateID;

    // All Fees collected
    uint256 public collectedFees;

    // All buyBackPrice(s) ensures proper spending
    uint256 public buyBackPrices;

    // Games that are allowed to use merchant
    mapping(address => uint256) public whitelist

    //TemplatedID count per game. Needed by templateIdsByGame()
    mapping(address => uint256) public totalItemsForSaleByGame;

    modifier isDevOf(address _game){
        require msg.sender == devOf(_game), "Merchant: Caller is not the Game developer.");
        _;
    }

    modifier inStock(address _game, uint256 _templateID) {
        Items memory item = itemByGame[_game][_templateID];
        require(item.stock > 0 || item.priceSystem == 2, "Merchant: Item requested is out of stock" );
        _;

    }

    constructor(uint256 _inventoryFee, IInventory _Inventory, IERC20 _Vidya, address _vault){

        inventoryFee = _inventoryFee;
        Inventory = _Inventory;
        Vidya = _Vidya;
        vault = _vault;

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
        Items memory item =  itemByGame[_game][_templateID];

        // item price + devfee
        // does not include inventory fee because this is for the dev to pay upon listing new items
        return item.price + devFee(_game);
    }

    // Get features and equipmentPosition of item by game
    // Helps prevent stack too deep error in sellTemplateId() function
    function detailsOfItemByGame(address _game, uint256 _templateId)
        public
        view
        returns (uint8[] memory)
    {
        Items memory item = itemByGame[_game][_templateId];
        uint8[] memory details = new uint8[](5);
        details[0] = item.feature1;
        details[1] = item.feature2;
        details[2] = item.feature3;
        details[3] = item.feature4;
        details[4] = item.equipmentPosition;
        return details;
    }

    // Public function to sell item to player (player is buying)
    function sellItem(uint256 _templateId, address _game, address _receiver)
        public
        returns (uint256, bool)
    {
        restock(_game, _templateId);
        return sellTemplateId(_templateId, _game);
    }

    // Sells a _templateId from _game (player is buying)
    function sellTemplateId(uint256 _templateId, address _game, address _receiver, uint256 _amount)
        internal
        
        inStock(_game, _templateId)
        returns (uint256, bool)
    {

        Items storage item = itemByGame[_game][_templateID];

        // Transfer buyBackPrice to Merchant contract
        if(item.buyBackPrice > 0){
            Vidya.safeTransferFrom(msg.sender, address(this), item.buyBackPrice);
        }
        // Transfer dev fee to game developer
        if(devFee(_game) > 0){
            Vidya.safeTransferFrom(msg.sender, devOf(_game), devFee(_game));
        }
        //Sends Profits to Vault
        uint256 _VP = item.price - item.buyBackPrice;
        Vidya.safeTransferFrom(msg.sender, vault, _VP);

        // Track the buyBackPrices
        buyBackPrices = buyBackPrice + buyBackPrices;

        if(item.priceSystem == 2){
            uint256 increase = item.price * item.rate / 100;
            item.price += increase;
        }else{
            //Remove Stock if in system 1
            item.stock -= _amount;
        }

        // Materialize
        uint256 tokenId = Inventory.createItemFromTemplate(
            _templateId,
            item.feature1,
            item.feature2,
            item.feature3,
            item.feature4,
            item.equipmentPosition,
            _amount,
            _receiver
        );

        templateIDByTokenID[tokenID] = _templateID;
        
        
        // tokenId of the item sold to player
        return (tokenId, true);
    }

    // "buys" a token back from the player (burns the token and sends buyBackPrice to player)
    function buyTokenId(uint256 _tokenId, address _game, address _holder, uint256 _amount)
        external
        returns (uint256)
    {
        uint256 templateIds = inventory.allItems(_tokenID)._templateId;

        Items storage item = itemByGame[_game][templateID];
 
        Inventory.burn(_holder, _tokenId, _amount);
        item.stock += _amount;

        Vidya.safeTransfer(msg.sender, item.buyBackPrice);

        // Track the buyBackPrices
        buyBackPrices -= item.buyBackPrice;

        return templateId;
    }
// Restocks an item
    function restock(address _game, uint256 _templateId) internal {
        Items storage item = itemByGame[_game][_templateId];
        if(item.priceSystem == 1){
            if (block.timestamp - item.restockTime >= item.cooldownTime) {
                // Restock the item
                item.stock = item.stockCap;
                item.restockTime = uint32(now);
            }
        }
    }

    /* Admin Functions */

    function updateInventoryFee(uint256 _fee) external onlyOwner {
        inventoryFee = _fee;
    }    

    function updateWhitelist(address _game, bool _status) external onlyOwner {
        whitelist[_game] = _status;
    }

    function withdrawProfit() external onlyOwner {
        uint256 profit = profits();
        // Send the tokens
        token.transfer(owner, profit);
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
        uint8[] calldata _details,
        uint8 _priceSystem,
        uint256 rate;
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
        require(Inventory.GameApproved(_templateID, _game), "Merchant: Game is not approved");
        Items memory item;
        
        if(gamesByTemplate[_templateId].lentgh > 0){

            item = itemByGame[gamesByTemplate[_templateID][0]];

        }else{
            item = Items(
                _game,
                _templateId,
                0,
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
                _priceSystem,
                _rate
            )
        }
        // Transfer the listing fee to owner
        Vidya.safeTransferFrom(msg.sender, owner, inventoryFee);

        // Update fees-to-inventory tracker
        collectedFees += inventoryFee;

        totalItemsForSaleByGame[_game]++;
        uint256 index = allItems.length
        itemByGame[_game][_templateId] = Items(
                _game,
                _templateId,
                index,
                item.price,
                item.buyBackPrice,
                _stock,
                _stockCap,
                uint32(now),
                _cooldownTime,
                _details[0], // feature1
                _details[1], // feature2
                _details[2], // feature3
                _details[3], // feature4
                _details[4] // equipmentPosition
                item.priceSystem,
                item.rate
            )

        allItems.push(
            Items(
                _game,
                _templateId,
                index,
                item.price,
                item.buyBackPrice,
                _stock,
                _stockCap,
                uint32(now),
                _cooldownTime,
                _details[0], // feature1
                _details[1], // feature2
                _details[2], // feature3
                _details[3], // feature4
                _details[4] // equipmentPosition
                item.priceSystem,
                item.rate
            )
        );
        gamesByTemplate[_templateId].push(_game);
        templateIdsByGame[_game].push(_templateId);
    }


}