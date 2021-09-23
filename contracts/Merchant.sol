// SPDX-License-Identifier: MIT

pragma solidity ^0.5.0;

/***
 * Merchant, how it should work 
 * 
 * Allows game (iGame) developers to list items for sale 
 * Only the game developer can add their items 
 * Requires the item (templateId) to exist in the iInventory contract (only team3d admin can add new templates into iInventory). Existing templates have supply of at least 1
 * Item buyBackPrice cannot be bigger than price 
 * Requires the game to be whitelisted by Merchant admin 
 * Game dev pays the iInventory contract listing fee 
 * While it costs VIDYA to list the item, in theory dev should earn back profit for each sale (dev fee is called from their own game!)
 * 
 * Sells those items to users (mints into existence on the iInventory contract)
 * Runs restock every time, but actually restocks only when necessary (and allowed)
 * Item needs to be in stock 
 * Item price gets sent here to Merchant  
 * Dev fee gets sent to dev of game (devFee called from the game, so devs can adjust it)
 * Item is minted into existence on iInventory contract 
 * Ability to sell items like this in bulk 
 * 
 * Buys those items back from users (burns from the iInventory contract)
 * Burns the item (msg.sender needs to be owner obviously, otherwise reverts)
 * Sends buyBackPrice back to the user (which is why it can't be bigger than price)
 * 
 * iInventory should get item listing fees from game devs 
 * Admin should be able to withdraw Merchant's profits, excluding the buyBackPrice which should 
 * always be reserved in case all people "bank run" and sell all items back to Merchant 
 * */

// ERC20 token Interface 
interface ERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address who) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

// Inventory contract Interface. Mainnet address: 0x9680223f7069203e361f55fefc89b7c1a952cdcc
contract iInventory {
	function getIndividualCount(uint256 _templateId) public view returns(uint256);
    function getTemplateIDsByTokenIDs(uint[] memory _tokenIds) public view returns(uint[] memory);
    function createFromTemplate(uint256 _templateId, uint8 _feature1, uint8 _feature2, uint8 _feature3, uint8 _feature4, uint8 _equipmentPosition) public returns(uint256);
    function burn(uint256 _tokenId) public returns(bool);
}

contract iGame {
    function devFee() public view returns(uint256);
    function developer() public view returns(address);
}

contract Merchant {
    using SafeMath for uint256;
    
    constructor(uint256 _inventoryFee) public {
        _admin = msg.sender;
		inventoryFee = _inventoryFee;
    }
    
    address public _admin;
    address public inventory    = address(0x9680223F7069203E361f55fEFC89B7c1A952CDcc);
    address public vidya        = address(0x3D3D35bb9bEC23b06Ca00fe472b50E7A4c692C30);

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
		
		// Inventory specific 
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

    // Things 
    iInventory inv = iInventory(inventory);
    ERC20 token = ERC20(vidya);

	// Games that are allowed to use merchant's services
	// This is for game devs and who can add or edit items etc. 
	mapping(address => bool) public whitelist;
	
	// TemplateId count per game. Needed by templateIdsByGame() 
	mapping(address => uint256) public totalItemsForSaleByGame;

    // Admin only functions 
    modifier admin() {
        require(msg.sender == _admin, "Merchant: Admin only function");
        _;
    }
	
	// Game developer only functions 
	modifier isDevOf(address _game) {
		require(msg.sender == devOf(_game), "Merchant: Msg.sender is not the Game developer");
		_;
	}
	
	// Check if the item is in stock 
	modifier inStock(address _game, uint256 _templateId) {
	    (, , , , , uint256 stock, , , , , , , ) = itemByGame(_game, _templateId);
	    require(stock > 0, "Merchant: Item requested is out of stock");
	    _;
	}
	
	// Function to return the Merchant's profit 
	function profits() public view returns(uint256) {
	    return SafeMath.sub(token.balanceOf(address(this)), buyBackPrices);
	}

    // Function to return the dev of _game 
    function devOf(address _game) public view returns(address) {
        iGame game = iGame(_game); 
        return game.developer();
    }
    
    // Function to return the devFee of _game 
    function devFee(address _game) public view returns(uint256) {
        iGame game = iGame(_game); 
        return game.devFee();
    }

    // Function to return the total price of _templateId from _game a player is expected to pay
    function sellPrice(uint256 _templateId, address _game) public view returns(uint256) {
        (, , , uint256 price, , , , , , , , , ) = itemByGame(_game, _templateId);
        // item price + devfee
        // does not include inventory fee because this is for the dev to pay upon listing new items 
        return SafeMath.add(price, devFee(_game));
    }

    // Get A item from _game by _templateId
    function itemByGame(
        address _game, 
        uint256 _templateId
    ) 
        public 
        view 
        returns(
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
        for(uint i = 0; i < allItems.length; i++) {
            if(allItems[i].game == _game && allItems[i].templateId == _templateId) {
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
    function templateIdsByGame(address _game) public view returns(uint256[] memory) {
        uint256[] memory templateIds = new uint256[](totalItemsForSaleByGame[_game]);
        for(uint i = 0; i < allItems.length; i++) {
            if(allItems[i].game == _game) {
                templateIds[i] = allItems[i].templateId;
            }
        }
        return templateIds;
    }
    
    // Get features and equipmentPosition of item by game 
    // Helps prevent stack too deep error in sellTemplateId() function 
    function detailsOfItemByGame(address _game, uint256 _templateId) public view returns(uint8[] memory) {
        (, , , , , , , , uint8 feature1, uint8 feature2, uint8 feature3, uint8 feature4, uint8 equipmentPosition) = itemByGame(_game, _templateId);
        uint8[] memory details = new uint8[](5);
        details[0] = feature1;
        details[1] = feature2;
        details[2] = feature3;
        details[3] = feature4;
        details[4] = equipmentPosition;
        return details;
    }
    
    // Public function to sell item to player (player is buying)
    function sellItem(uint256 _templateId, address _game) public returns(uint256, bool) {
        restock(_game, _templateId);
        return sellTemplateId(_templateId, _game);
    }
    
    // Sells a _templateId from _game (player is buying)
    function sellTemplateId(
		uint256 _templateId, 
		address _game
	) 
		internal 
		inStock(_game, _templateId)
		returns(uint256, bool)
	{
	    (, , , uint256 price, uint256 buyBackPrice, , , , , , , , ) = itemByGame(_game, _templateId);
	    uint8[] memory details = new uint8[](5);
	    details = detailsOfItemByGame(_game, _templateId);

        // Transfer price to Merchant contract
        require(token.transferFrom(msg.sender, address(this), price) == true, "Merchant: Token transfer to Merchant did not succeed");
        
        // Transfer dev fee to game developer
        require(token.transferFrom(msg.sender, devOf(_game), devFee(_game)) == true, "Merchant: Token transfer to Dev did not succeed");
        
	    // Track the buyBackPrices
	    buyBackPrices = SafeMath.add(buyBackPrice, buyBackPrices);

        // Materialize
        uint256 tokenId = inv.createFromTemplate(_templateId, details[0], details[1], details[2], details[3], details[4]);

        // tokenId of the item sold to player
        return (tokenId, true);
    }
    
    // Sells multiple items of the same _templateId by _game 
    function sellBulkTemplateId(address _game, uint256 _templateId, uint256 _amount) public {
        for(uint i = 0; i < _amount; i++) {
            sellItem(_templateId, _game);
        }
    }
    
    // "buys" a token back from the player (burns the token and sends buyBackPrice to player)
    function buyTokenId(uint256 _tokenId, address _game) public returns(uint256) {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = _tokenId;
        uint256[] memory templateIds = new uint256[](1);
        templateIds = inv.getTemplateIDsByTokenIDs(tokenIds);
        uint256 templateId = templateIds[0];
        (, , , , uint256 buyBackPrice, , , , , , , , ) = itemByGame(_game, templateId);
        require(inv.burn(_tokenId), "Merchant: Token burn failed");
        require(token.transfer(msg.sender, buyBackPrice) == true, "Merchant: Token transfer did not succeed");
        
	    // Track the buyBackPrices
	    buyBackPrices = SafeMath.sub(buyBackPrices, buyBackPrice);
        return templateId;
    }

    // Restocks an item 
    function restock(address _game, uint256 _templateId) internal {
        (, uint256 index, , , , , uint32 restockTime, uint32 cooldownTime, , , , , ) = itemByGame(_game, _templateId);
        if(now - restockTime >= cooldownTime) {
            // Restock the item 
            allItems[index].stock = allItems[index].stockCap;
            allItems[index].restockTime = uint32(now);
        }
    }

    
    
    
    /* ADMIN FUNCTIONS */
    
    function updateInventoryFee(uint256 _fee) external admin {
        inventoryFee = _fee;
    } 
    
    function updateWhitelist(address _game, bool _status) external admin {
        whitelist[_game] = _status;
    }
    
    function withdrawProfit() external admin {
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
    ) 
	    external 
	    isDevOf(_game)
	{
	    require(_buyBackPrice <= _price, "Merchant: Buyback price cannot be bigger than item price"); // this would be very bad if allowed! 
		require(whitelist[_game], "Merchant: Game is not whitelisted");
		
		uint256 totalSupply = inv.getIndividualCount(_templateId);
		
		// Fails when totalSupply of template is 0. Not added by admin to inventory contract
		require(totalSupply > 0, "Merchant: Trying to add item that does not exist yet");
		
		// Transfer the listing fee to Inventory
		require(token.transferFrom(msg.sender, inventory, inventoryFee) == true, "Merchant: Token transfer did not succeed");
		
		// Update fees-to-inventory tracker 
		collectedFees = SafeMath.add(inventoryFee, collectedFees);
		
		totalItemsForSaleByGame[_game] = SafeMath.add(1, totalItemsForSaleByGame[_game]);
		
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


library SafeMath {
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
          return 0;
        }
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a / b;
        return c;
    }
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        return a - b;
    }
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }
}