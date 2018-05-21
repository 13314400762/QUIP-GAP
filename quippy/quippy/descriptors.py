# HQ XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# HQ X
# HQ X   quippy: Python interface to QUIP atomistic simulation library
# HQ X
# HQ X   Copyright ST John 2017
# HQ X
# HQ X   These portions of the source code are released under the GNU General
# HQ X   Public License, version 2, http://www.gnu.org/copyleft/gpl.html
# HQ X
# HQ X   If you would like to license the source code under different terms,
# HQ X   please contact James Kermode, james.kermode@gmail.com
# HQ X
# HQ X   When using this software, please cite the following reference:
# HQ X
# HQ X   http://www.jrkermode.co.uk/quippy
# HQ X
# HQ XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

from functools import wraps

import numpy as np
from ase.atoms import Atoms as ASEAtoms

from quippy._descriptors import Descriptor as RawDescriptor
from quippy._descriptors import Soap, General_monomer
from quippy.oo_fortran import update_doc_string
from quippy.farray import fzeros
from quippy.atoms import Atoms
from quippy.util import dict_to_args_str

__all__ = ['Descriptor']


class DescriptorCalcResult(dict):
    """
    Results of a descriptor calculation.
    """
    def __getattr__(self, key): return self[key]
    def __setattr__(self, key, val): self[key] = val


def convert_atoms_types_iterable_method(method):
    """
    Decorator to transparently convert ASEAtoms objects into quippy Atoms, and
    to transparently iterate over a list of Atoms objects...
    """
    @wraps(method)
    def wrapper(self, at, *args, **kw):
        if isinstance(at, Atoms):
            return method(self, at, *args, **kw)
        elif isinstance(at, ASEAtoms):
            return method(self, Atoms(at), *args, **kw)
        else:
            return [wrapper(self, atelement, *args, **kw) for atelement in at]
    return wrapper


class Descriptor(RawDescriptor):
    __doc__ = update_doc_string(
        RawDescriptor.__doc__,
        """Pythonic wrapper for GAP descriptor module""",
        signature='Descriptor(args_str)')

    def __init__(self, args_str=None, **init_args):
        """
        Initialises Descriptor object and calculate number of dimensions and
        permutations.
        """
        if args_str is None:
            args_str = dict_to_args_str(init_args)
        RawDescriptor.__init__(self, args_str)
        self._n_dim = self.dimensions()
        self._n_perm = self.n_permutations()

    #: Number of dimensions
    n_dim = property(lambda self: self._n_dim)
    #: Number of permutations
    n_perm = property(lambda self: self._n_perm)

    def __len__(self):
        return self.n_dim

    def permutations(self):
        """
        Returns array containing all valid permutations of this descriptor.
        """
        perm = RawDescriptor.permutations(self, self.n_dim, self.n_perm)
        return np.array(perm).T

    @convert_atoms_types_iterable_method
    def count(self, at):
        """
        Returns how many descriptors of this type are found in the Atoms
        object.
        """
        return self.descriptor_sizes(at)[0]

    @convert_atoms_types_iterable_method
    def calc_descriptor(self, at, args_str=None, **calc_args):
        """
        Calculates all descriptors of this type in the Atoms object, and
        returns the array of descriptor values. Does not compute gradients; use
        calc(at, grad=True, ...) for that.
        """
        return self.calc(at, False, args_str, **calc_args).descriptor

    @convert_atoms_types_iterable_method
    def calc(self, at, grad=False, args_str=None, **calc_args):
        """
        Calculates all descriptors of this type in the Atoms object, and
        gradients if grad=True. Results can be accessed dictionary- or
        attribute-style; 'descriptor' contains descriptor values, 
        'descriptor_index_0based' contains the 0-based indices of the central 
        atom(s) in each descriptor, 'grad' contains gradients, 
        'grad_index_0based' contains indices to gradients (descriptor, atom).
        Cutoffs and gradients of cutoffs are also returned.
        """
        if args_str is None:
            args_str = dict_to_args_str(calc_args)

        n_index = fzeros(1,'i')
        n_desc, n_cross = self.descriptor_sizes(at,n_index=n_index)
        n_index = n_index[1]
        data = fzeros((self.n_dim, n_desc))
        cutoff = fzeros(n_desc)
        data_index = fzeros((n_index,n_desc),'i')

        if grad:
            # n_cross is number of cross-terms, proportional to n_desc
            data_grad = fzeros((self.n_dim, 3 ,n_cross))
            data_grad_index = fzeros((2, n_cross), 'i')
            cutoff_grad = fzeros((3 ,n_cross))

        if not grad:
            RawDescriptor.calc(self, at, descriptor_out=data, covariance_cutoff=cutoff, 
                    descriptor_index=data_index, args_str=args_str)
        else:
            RawDescriptor.calc(self, at, descriptor_out=data, covariance_cutoff=cutoff,
                    descriptor_index=data_index, grad_descriptor_out=data_grad, 
                    grad_descriptor_index=data_grad_index, grad_covariance_cutoff=cutoff_grad,
                    args_str=args_str)

        results = DescriptorCalcResult()
        convert = lambda data: np.array(data).T
        results.descriptor = convert(data)
        results.cutoff = convert(cutoff)
        results.descriptor_index_0based = convert(data_index-1)
        if grad:
            results.grad = convert(data_grad)
            results.grad_index_0based = convert(data_grad_index-1)
            results.cutoff_grad = convert(cutoff_grad)

        return results

