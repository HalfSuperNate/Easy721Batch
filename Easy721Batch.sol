// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC721PsiBurnable, ERC721Psi} from "./ERC721Psi/extension/ERC721PsiBurnable.sol";
import {Admins} from "./Admins.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {LibString} from "solady/src/utils/LibString.sol";
import {Base64} from "solady/src/utils/Base64.sol";

contract Easy721Batch is ERC721PsiBurnable, ReentrancyGuard, Admins {

    constructor(string memory name, string memory symbol) ERC721Psi(name, symbol) Admins(msg.sender) {}

    using LibString for uint256;
    using LibString for string;
    using Base64 for *;

    mapping(uint => uint[2]) private batchRange;
    mapping(uint => string) private batchName;
    mapping(uint => string) private batchDescription;
    mapping(uint => string) private batchImage;
    mapping(uint => string) private batchAnimationURL;
    uint256 public batchId;
    uint256 public cost;
    uint256 public mintCutoff;
    address public payments;
    bool public paused;

    error TokenDoesNotExist();
    error BatchDoesNotExist();
    error SkewedStartEnd();
    error BatchStartMustBeGreaterThanLastBatchEnd();
    error ErrorMintTxPrice();
    error OverMintLimit();
    error Paused();

    /**
     * @dev Allows admins to create a new batch.
     * @param _batchStart The batch starting token ID.
     * @param _batchEnd The batch ending token ID.
     * @param _Name The name for the tokens in this batch.
     * @param _Description The description for the tokens in this batch.
     * @param _Image The image uri for the tokens in this batch.
     * @param _Animation The animation uri for the tokens in this batch.
     */
    function createBatch(uint256 _batchStart, uint256 _batchEnd, string calldata _Name, string calldata _Description, string calldata _Image, string calldata _Animation) external onlyAdmins {
        if (_batchStart > _batchEnd) revert SkewedStartEnd();
        if (_batchStart <= batchRange[batchId][1]) revert BatchStartMustBeGreaterThanLastBatchEnd();
        batchId++;
        batchRange[batchId][0] = _batchStart;
        batchRange[batchId][1] = _batchEnd;
        batchName[batchId] = _Name;
        batchDescription[batchId] = _Description;
        batchImage[batchId] = _Image;
        if(!compareStrings(_Animation,"none")){
            batchAnimationURL[batchId] = _Animation;
        }
    }

    /**
     * @dev Allows admins to edit batch data.
     * @param _batchId The batch to edit.
     * @param _batchStart The batch starting token ID.
     * @param _batchEnd The batch ending token ID.
     * @param _Name The name for the tokens in this batch.
     * @param _Description The description for the tokens in this batch.
     * @param _Image The image uri for the tokens in this batch.
     * @param _Animation The animation uri for the tokens in this batch.
     */
    function editBatch(uint256 _batchId, uint256 _batchStart, uint256 _batchEnd, string calldata _Name, string calldata _Description, string calldata _Image, string calldata _Animation) external onlyAdmins {
        if (_batchId == 0 || _batchId > batchId) revert BatchDoesNotExist();
        if(_batchStart != 0){
            batchRange[batchId][0] = _batchStart;
        }
        if(_batchEnd != 0){
            batchRange[batchId][1] = _batchEnd;
        }
        if(!compareStrings(_Name,"none")){
            batchName[batchId] = _Name;
        }
        if(!compareStrings(_Description,"none")){
            batchDescription[batchId] = _Description;
        }
        if(!compareStrings(_Image,"none")){
            batchImage[batchId] = _Image;
        }
        if(!compareStrings(_Animation,"none")){
            batchAnimationURL[batchId] = _Animation;
        }
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
     * @dev Allows users to mint an amount of tokens.
     * @param _amount The amount of tokens to mint.
     */
    function mint(uint256 _amount) external payable nonReentrant {
        if (paused) revert Paused();
        if ((totalSupply() - 1) + _amount > mintCutoff) revert OverMintLimit();
        if (msg.value < (cost * _amount)) revert ErrorMintTxPrice();
        _mint(msg.sender, _amount);
    }
    
    /**
     * @dev Returns metadata uri for a token ID .
     * @param tokenId The token ID to fetch metadata uri.
     */
    function tokenURI(uint256 tokenId) override public view returns (string memory) {
        if (!_exists(tokenId)) revert TokenDoesNotExist();

        uint256 _batch = getBatch(tokenId);
        if (_batch == 0) revert BatchDoesNotExist();
        
        string memory json = Base64.encode(bytes(string(abi.encodePacked(
            '{"name": "', 
            batchName[_batch], 
            ' #', 
            tokenId.toString(), 
            '", "description": "', 
            batchDescription[_batch], 
            '", "image": "', 
            batchImage[_batch], 
            '", "animation_url": "', 
            batchAnimationURL[_batch], 
            '"}'))));

        return string(abi.encodePacked('data:application/json;base64,', json));
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
    function setCost(uint256 _newCost) public onlyAdmins {
        cost = _newCost;
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
