// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../owner/Operator.sol";
import "../interfaces/ITaxable.sol";
import "../interfaces/IRouter.sol";
import "../interfaces/IERC20.sol";

contract TaxOfficeV2 is Operator {
    using SafeMath for uint256;

    address public optomb = address(0xb48A5cBb404b0C0903e00E638a5F545c96a12202); 
    address public weth = address(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);
    address public uniRouter = address(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);

    mapping(address => bool) public taxExclusionEnabled;

    function setTaxTiersTwap(uint8 _index, uint256 _value)
        public
        onlyOperator
        returns (bool)
    {
        return ITaxable(optomb).setTaxTiersTwap(_index, _value);
    }

    function setTaxTiersRate(uint8 _index, uint256 _value)
        public
        onlyOperator
        returns (bool)
    {
        return ITaxable(optomb).setTaxTiersRate(_index, _value);
    }

    function enableAutoCalculateTax() public onlyOperator {
        ITaxable(optomb).enableAutoCalculateTax();
    }

    function disableAutoCalculateTax() public onlyOperator {
        ITaxable(optomb).disableAutoCalculateTax();
    }

    function setTaxRate(uint256 _taxRate) public onlyOperator {
        ITaxable(optomb).setTaxRate(_taxRate);
    }

    function setBurnThreshold(uint256 _burnThreshold) public onlyOperator {
        ITaxable(optomb).setBurnThreshold(_burnThreshold);
    }

    function setTaxCollectorAddress(address _taxCollectorAddress)
        public
        onlyOperator
    {
        ITaxable(optomb).setTaxCollectorAddress(_taxCollectorAddress);
    }

    function excludeAddressFromTax(address _address)
        external
        onlyOperator
        returns (bool)
    {
        return _excludeAddressFromTax(_address);
    }

    function _excludeAddressFromTax(address _address) private returns (bool) {
        if (!ITaxable(optomb).isAddressExcluded(_address)) {
            return ITaxable(optomb).excludeAddress(_address);
        }
    }

    function includeAddressInTax(address _address)
        external
        onlyOperator
        returns (bool)
    {
        return _includeAddressInTax(_address);
    }

    function _includeAddressInTax(address _address) private returns (bool) {
        if (ITaxable(optomb).isAddressExcluded(_address)) {
            return ITaxable(optomb).includeAddress(_address);
        }
    }

    function taxRate() external returns (uint256) {
        return ITaxable(optomb).taxRate();
    }

    function addLiquidityTaxFree(
        address token,
        uint256 amtOPTomb,
        uint256 amtToken,
        uint256 amtOPTombMin,
        uint256 amtTokenMin
    )
        external
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(amtOPTomb != 0 && amtToken != 0, "amounts can't be 0");
        _excludeAddressFromTax(msg.sender);

        IERC20(optomb).transferFrom(msg.sender, address(this), amtOPTomb);
        IERC20(token).transferFrom(msg.sender, address(this), amtToken);
        _approveTokenIfNeeded(optomb, uniRouter);
        _approveTokenIfNeeded(token, uniRouter);

        _includeAddressInTax(msg.sender);

        uint256 resultAmtOPTomb;
        uint256 resultAmtToken;
        uint256 liquidity;
        (resultAmtOPTomb, resultAmtToken, liquidity) = IRouter(
            uniRouter
        ).addLiquidity(
                optomb,
                token,
                false,
                amtOPTomb,
                amtToken,
                amtOPTombMin,
                amtTokenMin,
                msg.sender,
                block.timestamp
            );

        if (amtOPTomb.sub(resultAmtOPTomb) > 0) {
            IERC20(optomb).transfer(msg.sender, amtOPTomb.sub(resultAmtOPTomb));
        }
        if (amtToken.sub(resultAmtToken) > 0) {
            IERC20(token).transfer(msg.sender, amtToken.sub(resultAmtToken));
        }
        return (resultAmtOPTomb, resultAmtToken, liquidity);
    }

    function addLiquidityETHTaxFree(
        uint256 amtOPTomb,
        uint256 amtOPTombMin,
        uint256 amtEthMin
    )
        external
        payable
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(amtOPTomb != 0 && msg.value != 0, "amounts can't be 0");
        _excludeAddressFromTax(msg.sender);

        IERC20(optomb).transferFrom(msg.sender, address(this), amtOPTomb);
        _approveTokenIfNeeded(optomb, uniRouter);

        _includeAddressInTax(msg.sender);

        uint256 resultAmtOPTomb;
        uint256 resultAmtEth;
        uint256 liquidity;
        (resultAmtOPTomb, resultAmtEth, liquidity) = IRouter(uniRouter)
            .addLiquidityETH{value: msg.value}(
            optomb,
            false,
            amtOPTomb,
            amtOPTombMin,
            amtEthMin,
            msg.sender,
            block.timestamp
        );

        if (amtOPTomb.sub(resultAmtOPTomb) > 0) {
            IERC20(optomb).transfer(msg.sender, amtOPTomb.sub(resultAmtOPTomb));
        }
        return (resultAmtOPTomb, resultAmtEth, liquidity);
    }

    function setTaxableOPTombOracle(address _optombOracle) external onlyOperator {
        ITaxable(optomb).setOPTombOracle(_optombOracle);
    }

    function transferTaxOffice(address _newTaxOffice) external onlyOperator {
        ITaxable(optomb).setTaxOffice(_newTaxOffice);
    }

    function taxFreeTransferFrom(
        address _sender,
        address _recipient,
        uint256 _amt
    ) external {
        require(
            taxExclusionEnabled[msg.sender],
            "Address not approved for tax free transfers"
        );
        _excludeAddressFromTax(_sender);
        IERC20(optomb).transferFrom(_sender, _recipient, _amt);
        _includeAddressInTax(_sender);
    }

    function setTaxExclusionForAddress(address _address, bool _excluded)
        external
        onlyOperator
    {
        taxExclusionEnabled[_address] = _excluded;
    }

    function _approveTokenIfNeeded(address _token, address _router) private {
        if (IERC20(_token).allowance(address(this), _router) == 0) {
            IERC20(_token).approve(_router, type(uint256).max);
        }
    }
}