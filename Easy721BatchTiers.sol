// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// deployed: https://polygonscan.com/address/0x15f5ed58276ddb7ddf8fef732eae7c2428d0b2b8

import {ERC721PsiBurnable, ERC721Psi} from "./ERC721Psi/extension/ERC721PsiBurnable.sol";
import {Admins} from "./Admins.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {LibString} from "solady/src/utils/LibString.sol";
import {Base64} from "solady/src/utils/Base64.sol";

contract Easy721BatchTiers is ERC721PsiBurnable, ReentrancyGuard, Admins {

    constructor(string memory name, string memory symbol, uint256 initCutoff) ERC721Psi(name, symbol) Admins(msg.sender) {
        mintCutoff = initCutoff;
        _mint(msg.sender, 1); //mints the 0 token
        paused = true;
    }

    using LibString for uint256;
    using LibString for string;
    using Base64 for *;

    mapping(uint => uint) public cost;
    mapping(uint => uint[2]) private batchRange;
    mapping(uint => string) private batchName;
    mapping(uint => string) private batchDescription;
    mapping(uint => string) private batchImage;
    mapping(uint => string) private batchAnimationURL;
    mapping(uint => string[2]) private batchContentExt;
    mapping(uint => bool) private batchOnChainMetadata;
    mapping(uint => bool[2]) private batchContentByID;
    mapping(address => uint) private freeClaim;
    mapping(address => uint) private onTier; // 0 = public
    uint256 public batchId;
    uint256 public mintCutoff;
    address public payments;
    bool public paused;

    error TokenDoesNotExist();
    error BatchDoesNotExist();
    error SkewedStartEnd();
    error SkewedArray();
    error UsersRequired();
    error BatchStartMustBeGreaterThanLastBatchEnd();
    error ErrorMintTxPrice();
    error OverMintLimit();
    error Paused();

    /**
     * @dev Allows admins to create a new batch.
     * @param _onChainMetadata State if metadata is on chain.
     * @param _batchRange The batch starting, ending token ID.
     * @param _Name The name for the tokens in this batch.
     * @param _Description The description for the tokens in this batch.
     * @param _Image The image uri for the tokens in this batch.
     * @param _Animation The animation uri for the tokens in this batch.
     * @param _useContentByID State[0] if using ImageURI/tokenId or metadata/tokenId, State[1] if using animationURI/tokenId or metadata/tokenId.extension.
     * @param _uriExt The (image uri extension and animation url extension) or (metadata uri and extension) for the tokens in this batch.
     */
    function createBatch(bool _onChainMetadata, uint256[2] calldata _batchRange, string calldata _Name, string calldata _Description, string calldata _Image, string calldata _Animation, bool[2] calldata _useContentByID, string[2] memory _uriExt) external onlyAdmins {
        if (_batchRange[0] > _batchRange[1]) revert SkewedStartEnd();
        if (_batchRange[0] <= batchRange[batchId][1]) revert BatchStartMustBeGreaterThanLastBatchEnd();
        batchId++;
        batchOnChainMetadata[batchId] = _onChainMetadata;
        batchRange[batchId] = _batchRange;
        batchName[batchId] = _Name;
        if (_onChainMetadata) {
            batchDescription[batchId] = _Description;
            batchImage[batchId] = _Image;
            if(!compareStrings(_Animation,"none")){
                batchAnimationURL[batchId] = _Animation;
            }
        }

        batchContentExt[batchId] = _uriExt;
        
        batchContentByID[batchId] = _useContentByID;
    }

    /**
     * @dev Allows admins to edit batch data.
     * @param _batchId The batch to edit.
     * @param _batchRange The batch starting, ending token ID.
     * @param _Name The name for the tokens in this batch.
     * @param _Description The description for the tokens in this batch.
     * @param _Image The image uri for the tokens in this batch.
     * @param _Animation The animation uri for the tokens in this batch.
     * @param _onChainUseContentByID State[0] State if on chain metadata, State[1] if using ImageURI/tokenId or metadata/tokenId, State[2] if using animationURI/tokenId or metadata/tokenId.extension.
     * @param _uriExt The (image uri extension and animation url extension) or (metadata uri and extension) for the tokens in this batch.
     */
    function editBatch(uint256 _batchId, uint256[2] calldata _batchRange, string calldata _Name, string calldata _Description, string calldata _Image, string calldata _Animation, bool[3] calldata _onChainUseContentByID, string[2] memory _uriExt) external onlyAdmins {
        if (_batchId > batchId) revert BatchDoesNotExist();
        if (_batchId != 0) {
            if(_batchRange[0] != 0){
                batchRange[_batchId][0] = _batchRange[0];
            }
            if(_batchRange[1] != 0){
                batchRange[_batchId][1] = _batchRange[1];
            }
        }
        if(!compareStrings(_Name,"none")){
            batchName[_batchId] = _Name;
        }
        if(!compareStrings(_Description,"none")){
            batchDescription[_batchId] = _Description;
        }
        if(!compareStrings(_Image,"none")){
            batchImage[_batchId] = _Image;
        }
        if(!compareStrings(_Animation,"none")){
            batchAnimationURL[_batchId] = _Animation;
        }
        batchContentExt[_batchId] = _uriExt;
        
        batchOnChainMetadata[_batchId] = _onChainUseContentByID[0];
        batchContentByID[_batchId][0] = _onChainUseContentByID[1];
        batchContentByID[_batchId][1] = _onChainUseContentByID[2];
    }

    /**
     * @dev Allows admins to mint an amount of tokens.
     * @param _amount The amount of tokens to mint.
     */
    function ownerMint(uint256 _amount) external onlyAdmins {
        _mint(msg.sender, _amount);
    }

    /**
     * @dev Allows admins to mint/airdrop to a list of users.
     * @param _to The list of wallet addresses to mint/airdrop to.
     * Note: A single tokem is minted for each address, multiple same addresses are allowed.
     */
    function airdrop(address[] calldata _to) external onlyAdmins {
        for (uint256 i = 0; i < _to.length; i++) {
            _mint(_to[i], 1);
        }
    }

    /**
     * @dev Allows admins to set a tier and or free claims for users.
     * @param _users The list of wallet addresses to set tier or free claims.
     * @param _tiers The tier to set for the user.
     * @param _freeClaims The number of free claims for the user.
     */
    function setTiersClaims(address[] calldata _users, uint256[] calldata _tiers, uint256[] calldata _freeClaims) external onlyAdmins {
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
                freeClaim[_users[i]] = 0;
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
                freeClaim[_users[i]] = _freeClaims[i];
            }
            return;
        }

        if (_mode == 11) {
            // set tier, set free claim
            for (uint256 i = 0; i < _users.length; i++) {
                onTier[_users[i]] = _tiers[i];
                freeClaim[_users[i]] = _freeClaims[i];
            }
            return;
        }
    }

    /**
     * @dev Allows users to mint an amount of tokens.
     * @param _amount The amount of tokens to mint.
     */
    function mint(address _to, uint256 _amount) external payable nonReentrant {
        if (!checkIfAdmin()) {
            if (paused) revert Paused();
            if ((totalSupply() - 1) + _amount > mintCutoff) revert OverMintLimit();
            if (msg.value < getCost(_amount)) revert ErrorMintTxPrice();

            if (freeClaim[msg.sender] != 0) {
                if (_amount >= freeClaim[msg.sender]){
                    freeClaim[msg.sender] = 0;
                } else{
                    freeClaim[msg.sender] -= _amount;
                }
            }
        }
        _mint(_to, _amount);
    }

    /**
     * @dev Returns cost for an amount of tokens in WEI.
     * @param _amount The amount of tokens to calculate cost.
     * 1 ETH = 10^18 WEI
     * Note: Use https://etherscan.io/unitconverter for ETH to WEI conversions.
     */
    function getCost(uint256 _amount) public view returns (uint256) {
        uint256 calcAmount = _amount;
        if (freeClaim[msg.sender] != 0) {
            if (_amount >= freeClaim[msg.sender]){
                calcAmount -= freeClaim[msg.sender];
            } else{
                calcAmount = 0;
            }
        }
        return (cost[onTier[msg.sender]] * calcAmount);
    }
    
    /**
     * @dev Returns metadata uri for a token ID.
     * @param tokenId The token ID to fetch metadata uri.
     */
    function tokenURI(uint256 tokenId) override public view returns (string memory) {
        if (!_exists(tokenId)) revert TokenDoesNotExist();

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
            '"}'))));

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

    /**
     * @dev Returns the following batch data: 
     * token range, name, description, image uri, animation uri
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
            batchImage[_batchId],
            ', ',
            batchAnimationURL[_batchId]
        ));
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
     * @dev Admin can set the new cost in WEI.
     * 1 ETH = 10^18 WEI
     * Note: Use https://etherscan.io/unitconverter for ETH to WEI conversions.
     */
    function setCost(uint256 _tier, uint256 _newCost) public onlyAdmins {
        cost[_tier] = _newCost;
    }

    /**
     * @dev Admin can set the token ID to stop public mint.
     * @param _cutoffID The token ID that public mint will stop at.
     */
    function setCutoff(uint256 _cutoffID) public onlyAdmins {
        mintCutoff = _cutoffID;
    }

    /**
     * @dev Admin can set the payout address.
     * @param _address The new payout address.
     */
    function setPayoutAddress(address _address) external onlyAdmins{
        payments = payable(_address);
    }

    /**
     * @dev Admin can set pause state.
     * @param _pause Set to true for paused and false for unpause.
     */
    function setPause(bool _pause) external onlyAdmins{
        paused = _pause;
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
