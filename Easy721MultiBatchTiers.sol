// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Admins} from "./Admins.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {LibString} from "solady/src/utils/LibString.sol";
import {Base64} from "solady/src/utils/Base64.sol";

contract Easy721MultiBatchTiers is Context, ERC721, ReentrancyGuard, Admins{
    using LibString for uint256;
    using LibString for string;
    using Base64 for *;

    mapping(uint => uint) public cost;
    mapping(uint => uint) public discount;
    mapping(uint => uint[2]) private batchRange;
    mapping(uint => uint) private tokenNextToMintInBatch;
    mapping(uint => string) private batchName;
    mapping(uint => string) private batchDescription;
    mapping(uint => string) private batchExternalURL;
    mapping(uint => string) private batchImage;
    mapping(uint => string) private batchAnimationURL;
    mapping(uint => Attribute[]) public attributes;
    mapping(uint => string[2]) private batchContentExt;
    mapping(uint => bool) public batchPaused;
    mapping(uint => bool) private existed;
    mapping(uint => bool) private batchOnChainMetadata;
    mapping(uint => bool[2]) private batchContentByID;
    mapping(address => mapping(uint => uint)) private freeClaim;
    mapping(address => uint) private onTier; // 0 = public
    
    uint256 public batchId;
    address public payments;
    bool public paused;

    struct Attribute {
        uint8 display; // 0=string, 1=int_float, 2="boost_number", 3="boost_percentage", 4="number", 5="date"
        string trait; // "string" or "" for null
        string value;
    }

    error InvalidUser();
    error TokenDoesNotExist();
    error BatchDoesNotExist();
    error SkewedStartEnd();
    error SkewedArray();
    error UsersRequired();
    error BatchStartMustBeGreaterThanLastBatchEnd();
    error ErrorMintTxPrice();
    error OutOfRange();
    error OverMintLimit();
    error Paused();

    constructor(string memory name, string memory symbol) ERC721(name, symbol) Admins(msg.sender){
        _mint(msg.sender, 0); //mints the 0 token
        existed[0] = true;
        paused = true;
    }

    function _msgSender() internal view override(Context,Admins) returns (address) {
        return msg.sender;
    }

    function _msgData() internal pure override(Context,Admins) returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal pure override(Context,Admins) returns (uint256) {
        return 0;
    }

    /**
     * @dev Allows admins to create a new batch.
     * @param _onChainMetadata State if metadata is on chain.
     * @param _batchRange The batch starting, ending token ID.
     * @param _Metadata The name, description, externalURL, image, animationURL.
     * @param _useContentByID State[0] if using ImageURI/tokenId or metadata/tokenId, State[1] if using animationURI/tokenId or metadata/tokenId.extension.
     * @param _uriExt The (image uri extension and animation url extension) or (metadata uri and extension) for the tokens in this batch.
     */
    function createBatch(bool _onChainMetadata, uint256[2] calldata _batchRange, string[5] calldata _Metadata, bool[2] calldata _useContentByID, string[2] memory _uriExt) external onlyAdmins {
        if (_batchRange[0] > _batchRange[1]) revert SkewedStartEnd();
        if (_batchRange[0] <= batchRange[batchId][1]) revert BatchStartMustBeGreaterThanLastBatchEnd();
        batchId++;
        batchOnChainMetadata[batchId] = _onChainMetadata;
        batchRange[batchId] = _batchRange;
        tokenNextToMintInBatch[batchId] = _batchRange[0];
        batchName[batchId] = _Metadata[0];
        if (_onChainMetadata) {
            batchDescription[batchId] = _Metadata[1];
            batchExternalURL[batchId] = _Metadata[2];
            batchImage[batchId] = _Metadata[3];
            batchAnimationURL[batchId] = _Metadata[4];
        }

        batchContentExt[batchId] = _uriExt;
        batchContentByID[batchId] = _useContentByID;
        batchPaused[batchId] = true;
    }

    /**
     * @dev Allows admins to edit batch data.
     * @param _batchId The batch to edit.
     * @param _batchRange The batch starting, ending token ID.
     * @param _Metadata The name, description, externalURL, image, animationURL.
     * @param _onChainUseContentByID State[0] State if on chain metadata, State[1] if using ImageURI/tokenId or metadata/tokenId, State[2] if using animationURI/tokenId or metadata/tokenId.extension.
     * @param _uriExt The (image uri extension and animation url extension) or (metadata uri and extension) for the tokens in this batch.
     * Note: For _Metadata if a section has no change use "**" to ignore it.
     */
    function editBatch(uint256 _batchId, uint256[2] calldata _batchRange, string[5] calldata _Metadata, bool[3] calldata _onChainUseContentByID, string[2] memory _uriExt) external onlyAdmins {
        if (_batchId > batchId) revert BatchDoesNotExist();
        if (_batchId != 0) {
            if(_batchRange[0] != 0){
                if(tokenNextToMintInBatch[batchId] == batchRange[_batchId][0] && exists(_batchRange[0])){
                    tokenNextToMintInBatch[batchId] = _batchRange[0];
                }
                batchRange[_batchId][0] = _batchRange[0];
            }
            if(_batchRange[1] != 0){
                batchRange[_batchId][1] = _batchRange[1];
            }
        }
        if(!compareStrings(_Metadata[0],"**")){
            batchName[_batchId] = _Metadata[0];
        }
        if(!compareStrings(_Metadata[1],"**")){
            batchDescription[_batchId] = _Metadata[1];
        }
        if(!compareStrings(_Metadata[2],"**")){
            batchExternalURL[_batchId] = _Metadata[2];
        }
        if(!compareStrings(_Metadata[3],"**")){
            batchImage[_batchId] = _Metadata[3];
        }
        if(!compareStrings(_Metadata[4],"**")){
            batchAnimationURL[_batchId] = _Metadata[4];
        }
        batchContentExt[_batchId] = _uriExt;
        
        batchOnChainMetadata[_batchId] = _onChainUseContentByID[0];
        batchContentByID[_batchId][0] = _onChainUseContentByID[1];
        batchContentByID[_batchId][1] = _onChainUseContentByID[2];
    }

    /**
     * @dev Internal to check if a token was minted.
     * @param tokenId The token to check.
     */
    function exists(uint256 tokenId) internal view returns(bool) {
        return existed[tokenId];
    }

    /**
     * @dev Internal to mint tokens from a batch.
     * @param _to The address to mint to.
     * @param _batch The batch to mint from.
     * @param _amount The amount to mint from batch.
     */
    function batchMint(address _to, uint256 _batch, uint _amount) internal {
        if ((tokenNextToMintInBatch[_batch] - 1) + _amount > batchRange[_batch][1]) revert OverMintLimit();
        for (uint256 i = 0; i < _amount; i++) {
            _safeMint(_to, (tokenNextToMintInBatch[_batch] + i));
            existed[(tokenNextToMintInBatch[_batch] + i)] = true;
        }
        tokenNextToMintInBatch[_batch] += _amount;
    }

    /**
     * @dev Allows admins to mint a token.
     * @param _batch The batch to mint from.
     * @param _amount The amount to mint from batch.
     */
    function ownerMint(uint256 _batch, uint _amount) external onlyAdmins {
        batchMint(msg.sender, _batch, _amount);
    }

    /**
     * @dev Allows admins to mint/airdrop to a list of users.
     * @param _to The list of wallet addresses to mint/airdrop to.
     * @param _batch The batch to mint/airdrop from.
     * Note: A single token is minted for each address, multiple same addresses are allowed.
     */
    function airdrop(address[] calldata _to, uint[] calldata _batch) external onlyAdmins {
        if (_to.length != _batch.length) revert SkewedArray();
        for (uint256 i = 0; i < _to.length; i++) {
            batchMint(_to[i], _batch[i], 1);
        }
    }

    /**
     * @dev Allows users to mint an amount of tokens.
     * @param _to The address to mint to.
     * @param _batch The batch to mint from.
     * @param _amount The amount of tokens to mint.
     */
    function mint(address _to, uint256 _batch, uint256 _amount) external payable nonReentrant {
        if (!checkIfAdmin()) {
            if (paused || batchPaused[_batch]) revert Paused();
            if ((tokenNextToMintInBatch[_batch] - 1) + _amount > batchRange[_batch][1]) revert OverMintLimit();
            if (msg.value < getCost(_batch, _amount)) revert ErrorMintTxPrice();

            if (freeClaim[msg.sender][_batch] != 0) {
                if (_amount >= freeClaim[msg.sender][_batch]){
                    freeClaim[msg.sender][_batch] = 0;
                } else{
                    freeClaim[msg.sender][_batch] -= _amount;
                }
            }
        }
        batchMint(_to, _batch, _amount);
    }
    
    /**
     * @dev Returns metadata uri for a token ID.
     * @param tokenId The token ID to fetch metadata uri.
     */
    function tokenURI(uint256 tokenId) override public view returns (string memory) {
        if (!exists(tokenId)) revert TokenDoesNotExist();

        uint256 _batch = getBatch(tokenId);

        if (batchOnChainMetadata[_batch]) {
            string memory _image = batchImage[_batch];
            string memory _anim = batchAnimationURL[_batch];
            if (batchContentByID[_batch][0]) {
                _image = string(abi.encodePacked(_image, "/", tokenId.toString(), batchContentExt[_batch][0]));
            }
            if (batchContentByID[_batch][1]) {
                _anim = string(abi.encodePacked(_anim, "/", tokenId.toString(), batchContentExt[_batch][1]));
            }

            string memory json = Base64.encode(bytes(string(abi.encodePacked(
            '{"name": "', 
            batchName[_batch], 
            ' #', 
            tokenId.toString(), 
            '", "description": "', 
            batchDescription[_batch], 
            '", "image": "', 
            _image, 
            '", "animation_url": "', 
            _anim,
            '", "external_url": "', 
            batchExternalURL[_batch],
            '", "attributes": ', 
            getAttributes(_batch),
            '}'))));

            return string(abi.encodePacked('data:application/json;base64,', json));
        }
        
        if (batchContentByID[_batch][0] && batchContentByID[_batch][1]) {
            // metadataURI/tokenId.extension
            return string(abi.encodePacked(batchContentExt[_batch][0], "/", tokenId.toString(), batchContentExt[_batch][1]));
        }
        
        if (batchContentByID[_batch][0] && !batchContentByID[_batch][1]) {
            // metadataURI/tokenId
            return string(abi.encodePacked(batchContentExt[_batch][0], "/", tokenId.toString()));
        } else{
            // metadataURI
            return batchContentExt[_batch][0];
        }
    }

    function getAttributes(uint256 _batch) public view returns (string memory) {
        string memory _result;
        if (attributes[_batch].length != 0) {
            for (uint256 i = 0; i < attributes[_batch].length; i++) {
                if (i == attributes[_batch].length - 1) {
                    _result = string.concat(_result, "{", getDisplayType(_batch,i), getTraitType(_batch,i), getTraitValue(_batch,i), "}");
                } else{
                    _result = string.concat(_result, "{", getDisplayType(_batch,i), getTraitType(_batch,i), getTraitValue(_batch,i), "},");
                }
            }
        }
        return string.concat("[", _result, "]");
    }
    
    function getDisplayType(uint256 _batch, uint256 _index) internal view returns (string memory) {
        if (_index > attributes[_batch].length - 1) revert OutOfRange();
        if (attributes[_batch][_index].display <= 1) return "";
        if (attributes[_batch][_index].display == 2) return '"display_type":"boost_number",';
        if (attributes[_batch][_index].display == 3) return '"display_type":"boost_percentage",';
        if (attributes[_batch][_index].display == 4) return '"display_type":"number",';
        if (attributes[_batch][_index].display == 5) return '"display_type":"date",';
        return "";
    }

    function getTraitType(uint256 _batch, uint256 _index) internal view returns (string memory) {
        if (_index > attributes[_batch].length - 1) revert OutOfRange();
        string memory _result = compareStrings(attributes[_batch][_index].trait,"") ? "" : string.concat('"trait_type":"', attributes[_batch][_index].trait, '",');
        return _result;
    }

    function getTraitValue(uint256 _batch, uint256 _index) internal view returns (string memory) {
        if (_index > attributes[_batch].length - 1) revert OutOfRange();
        string memory _result = attributes[_batch][_index].display == 0 ? string.concat('"value":"', attributes[_batch][_index].value, '"') : string.concat('"value":', attributes[_batch][_index].value);
        return _result;
    }

    /**
     * @dev User can set new attributes for the specified batch.
     * @param _batch The batch to edit.
     * @param _displayType Use 0=string, 1=int_float, 2="boost_number", 3="boost_percentage", 4="number", 5="date".
     * @param _traitType Use "string" or "" for null.
     * @param _traitValue Use "string" if displayType is 0 or "numbers" for displayTypes 1-4, for option 5 use "unixTimeStampNumber".
     * Note: Example: 0, [0,1,2,3,4,5], ["","Lvl","Str","Hp","Mp","Birthday"], ["John","1.8","66","4","20","1703901173"]
     */
    function setAttributes(uint256 _batch, uint8[] calldata _displayType, string[] calldata _traitType, string[] calldata _traitValue) external onlyAdmins{
        delete attributes[_batch];
        Attribute memory newAttribute = Attribute({
            display: 0,
            trait: "",
            value: ""
        });
        for (uint256 i = 0; i < _displayType.length; i++) {
            newAttribute.display = _displayType[i];
            newAttribute.trait = _traitType[i];
            newAttribute.value = _traitValue[i];
            attributes[_batch].push(newAttribute);
        }
    }

    /**
     * @dev Returns the following batch data: 
     * token range, name, description, external url, image uri, animation uri
     * @param _batchId The batch ID to check.
     */
    function getBatchData(uint256 _batchId) public view returns(string memory) {
        return string(abi.encodePacked(
            batchRange[_batchId][0].toString(),
            ' - ', 
            batchRange[_batchId][1].toString(),
            ', ',
            batchName[_batchId],
            ', ',
            batchDescription[_batchId],
            ', ',
            batchExternalURL[_batchId],
            ', ',
            batchImage[_batchId],
            ', ',
            batchAnimationURL[_batchId]
        ));
    }

    /**
     * @dev Returns the next token ID to be minted from a batch.
     * @param _batch The batch to check.
     */
    function getNextToken(uint256 _batch) public view returns(uint) {
        if (tokenNextToMintInBatch[_batch] > batchRange[_batch][1]) revert OutOfRange();
        return tokenNextToMintInBatch[_batch];
    }

    /**
     * @dev Returns a batch ID from a token ID.
     * @param _tokenId The token ID to find which batch it resides in.
     */
    function getBatch(uint256 _tokenId) public view returns(uint) {
        for (uint256 i = 1; i < batchId + 1; i++) {
            if (_tokenId >= batchRange[i][0] && _tokenId <= batchRange[i][1]) {
                return i;
            }
        }
        return 0;
    }

    /**
     * @dev Returns cost for an amount of tokens in WEI.
     * @param _batch The batch to get cost from.
     * @param _amount The amount of tokens to calculate cost.
     * 1 ETH = 10^18 WEI
     * Note: Use https://etherscan.io/unitconverter for ETH to WEI conversions.
     */
    function getCost(uint256 _batch, uint256 _amount) public view returns (uint256) {
        uint256 calcAmount = _amount;
        if (freeClaim[msg.sender][_batch] != 0) {
            if (_amount >= freeClaim[msg.sender][_batch]){
                calcAmount -= freeClaim[msg.sender][_batch];
            } else{
                calcAmount = 0;
            }
        }
        if (onTier[msg.sender] != 0) {
            // discount if on tier list
            uint256 _discount = (cost[_batch] * calcAmount) * discount[onTier[msg.sender]] / 100;
            if ((cost[_batch] * calcAmount) - _discount <= 0) {
                return 0;
            } else{
                return (cost[_batch] * calcAmount) - _discount;
            }
            
        }
        return (cost[_batch] * calcAmount);
    }

    /**
     * @dev Admin can set the new cost in WEI.
     * @param _batch The batch to edit.
     * @param _newCost The new cost in WEI for the batch.
     * 1 ETH = 10^18 WEI
     * Note: Use https://etherscan.io/unitconverter for ETH to WEI conversions.
     */
    function setCost(uint256 _batch, uint256 _newCost) public onlyAdmins {
        cost[_batch] = _newCost;
    }

    /**
     * @dev Admin can set the new percentage discount.
     * Note: _discount cannot be more than 100 percent.
     */
    function setDiscount(uint256 _tier, uint256 _discount) public onlyAdmins {
        if (_discount > 100) revert OutOfRange();
        discount[_tier] = _discount;
    }

    /**
     * @dev Allows admins to set a tier and or free claims for users on a specified batch.
     * @param _users The list of wallet addresses to set tier or free claims.
     * @param _tiers The discount tier to set for the user.
     * @param _freeClaims The number of free claims for the user.
     * @param _batch The specified batch for free claims.
     * Note: A set discount tier for an address is applied for the entire collection, while free claims are specific to a batch.
     */
    function setTiersClaims(address[] calldata _users, uint256[] calldata _tiers, uint256[] calldata _freeClaims, uint256 _batch) external onlyAdmins {
        if (_users.length <= 0) revert UsersRequired();
        uint256 _mode = 0;
        if (_tiers.length != 0) {
            if (_tiers.length != _users.length) revert SkewedArray();
            _mode += 1;
        }
        if (_freeClaims.length != 0) {
            if (_freeClaims.length != _users.length) revert SkewedArray();
            _mode += 10;
        }

        if (_mode == 0) {
            // clear both tier and free claim
            for (uint256 i = 0; i < _users.length; i++) {
                onTier[_users[i]] = 0;
                freeClaim[_users[i]][_batch] = 0;
            }
            return;
        }

        if (_mode == 1) {
            // set tier, do not edit free claim
            for (uint256 i = 0; i < _users.length; i++) {
                onTier[_users[i]] = _tiers[i];
            }
            return;
        }

        if (_mode == 10) {
            // do not edit tier, set free claim
            for (uint256 i = 0; i < _users.length; i++) {
                freeClaim[_users[i]][_batch] = _freeClaims[i];
            }
            return;
        }

        if (_mode == 11) {
            // set tier, set free claim
            for (uint256 i = 0; i < _users.length; i++) {
                onTier[_users[i]] = _tiers[i];
                freeClaim[_users[i]][_batch] = _freeClaims[i];
            }
            return;
        }
    }

    /**
     * @dev Admin can set pause state.
     * @param _pause Set to true for paused and false for unpause.
     * Note: If true this will pause the entire collection.
     */
    function setPause(bool _pause) external onlyAdmins{
        paused = _pause;
    }

    /**
     * @dev Admin can set pause state for a batch.
     * @param _batch The batch to edit.
     * @param _pause Set to true for paused and false for unpause.
     * Note: Will pause or unpause only a specific batch.
     */
    function setBatchPause(uint256 _batch, bool _pause) external onlyAdmins{
        batchPaused[_batch] = _pause;
    }

    /**
     * @dev Admin can set the payout address.
     * @param _address The new payout address.
     */
    function setPayoutAddress(address _address) external onlyAdmins{
        payments = payable(_address);
    }

    /**
     * @dev Admin can pull funds to the payout address.
     */
    function withdraw() public payable onlyAdmins {
        require(payments != address(0), "Payout Address Must Be Set First");
        (bool success, ) = payable(payments).call{ value: address(this).balance } ("");
        require(success);
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }
}
