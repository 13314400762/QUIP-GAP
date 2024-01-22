# HQ XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# HQ X
# HQ X   quippy: Python interface to QUIP atomistic simulation library
# HQ X
# HQ X   Copyright James Kermode 2019
# HQ X
# HQ X   These portions of the source code are released under the GNU General
# HQ X   Public License, version 2, https://www.gnu.org/copyleft/gpl.html
# HQ X
# HQ X   If you would like to license the source code under different terms,
# HQ X   please contact James Kermode, james.kermode@gmail.com
# HQ X
# HQ X   When using this software, please cite the following reference:
# HQ X
# HQ X   https://www.jrkermode.co.uk/quippy
# HQ X
# HQ XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

import unittest
import os

import numpy as np
import ase
import ase.build
import json

import quippy
import quippytest


# ref data made using blah blah blah


@unittest.skipIf(os.environ['HAVE_GAP'] != '1', 'GAP support not enabled')
class Test_Descriptor(quippytest.QuippyTestCase):
    def setUp(self):
        #construct datasets
        dataset_info = {'mono_3': [{'cell': [[3.7804574864992735, 0.6403753687764577, 0.06556849361402822], [0.467610144212817, 5.856308497134963, 0.5393972906163427], [0.1079500911769212, 0.4621354535312472, 7.714439709469615]], 'scaled_positions': [[0.7378151104962647, 0.05620457452483585, 0.9350680241759733], [0.020110292391504636, 0.7424420259364064, 0.00978213247240678], [0.9703792428315547, 0.3795969541230244, 0.915752525406077], [0.46758128804998556, 0.5185019454280103, 0.34666952214277347], [0.21097003378217005, 0.6272781261534615, 0.5628044828510753]], 'numbers': [6, 6, 6, 6, 6]}, {'cell': [[4.450031624880567, 0.44191565330149124, 0.2926819547583543], [0.6459309497491833, 7.267216668605509, 0.3690387771710094], [0.1609005330846019, 0.7124139189445902, 9.451086529465591]], 'scaled_positions': [[0.32210944380314066, 0.1680898299705127, 0.4725754777692006], [0.15505261694269568, 0.8787718738799598, 0.4541108209136845], [0.2106943609868661, 0.12940703304200218, 0.40414273086642727], [0.18405190100266178, 0.0908581972642355, 0.2271246754887397], [0.21279351593456897, 0.8672601121928283, 0.48341958734757295], [0.1599065485309451, 0.9062662645188113, 0.2907088519892115], [0.6561420976591963, 0.650844357907304, 0.1674709288240801], [0.14242953896980537, 0.6045824148409813, 0.9945622169985299], [0.47403863943072444, 0.3449864890870252, 0.02899651119372415]], 'numbers': [6, 6, 6, 6, 6, 6, 6, 6, 6]}, {'cell': [[4.554397812064609, 0.6354407104858513, 0.5921588960561066], [0.32563712371652026, 6.977564851953197, 0.18602383694180633], [0.44309736940668826, 0.7471246630698813, 9.624454791243677]], 'scaled_positions': [[0.1631868520636991, 0.15156491065079125, 0.7342636386621795], [0.6645366464968023, 0.018656476953606727, 0.28199389463571267], [0.3273082025479276, 0.8937873147420282, 0.37633737307504156], [0.6849314528863337, 0.8640671657357293, 0.6171749745526651], [0.6582592177892379, 0.3813801419603481, 0.4276446932086827], [0.9582722084569038, 0.5062233645680481, 0.9406548758356109], [0.9338473620613611, 0.17356368518600074, 0.7813228136959918], [0.4094675653182981, 0.36165079532417943, 0.6483134513629402], [0.7991474647549547, 0.513680048215282, 0.22461546176160319]], 'numbers': [6, 6, 6, 6, 6, 6, 6, 6, 6]}], 'quad_3': [{'cell': [[4.055942622188628, 0.13207233700302512, 0.6067857412564778], [0.16824976872312936, 5.920153106710241, 0.21203133143454475], [0.19613602103069652, 0.010185982826157155, 8.410681981048068]], 'scaled_positions': [[0.1930743794636407, 0.22734956973439524, 0.881159498645289], [0.7751703118703634, 0.35558431268770585, 0.9761925368104483], [0.903139163703848, 0.3252229091987914, 0.00671330848933438], [0.5421022347910625, 0.7347194582172755, 0.0026140563965344477], [0.42766598017125135, 0.453787751883989, 0.761078396325939], [0.2268049609796886, 0.4164573629734901, 0.7103189098803314]], 'numbers': [23, 41, 42, 73, 23, 41]}, {'cell': [[4.348362703400225, 0.6846534550136543, 0.0254398960906846], [0.6298732134242532, 6.219171229074671, 0.016044807810003413], [0.6315662638257906, 0.5752111640102692, 8.819195831794705]], 'scaled_positions': [[0.2679416792604502, 0.583432685101674, 0.00016986803978757958], [0.010799695114256935, 0.6518424978536462, 0.8299083342195709], [0.6841300929400939, 0.9728741418400548, 0.1969614354611774], [0.4128838414741375, 0.12488824994497827, 0.7901527721438402], [0.583175074397211, 0.9031099036172244, 0.023452563642577973], [0.10184636893500787, 0.8614619364783734, 0.3965732498362363], [0.6657454941896441, 0.6128976214386175, 0.18892742410172425]], 'numbers': [23, 41, 42, 73, 23, 41, 42]}, {'cell': [[3.790005602811848, 0.24888872505794168, 0.5909420318076777], [0.035623201003269406, 5.766561620989214, 0.3992088382357873], [0.5830538310694123, 0.3458483399112265, 7.7814317782719025]], 'scaled_positions': [[0.250117433635772, 0.01701755279877004, 0.3342112814917262], [0.009648655521099392, 0.26972325004460873, 0.7315833324900424], [0.48776760687988374, 0.324552723194103, 0.32244844306451204], [0.36654318944537967, 0.7150128064806731, 0.39935329597927405], [0.981349407692744, 0.03277998876352195, 0.6940014623541534]], 'numbers': [23, 41, 42, 73, 23]}]}
        self.datasets = dict()
        for name, info in dataset_info.items():
            self.datasets[name] = [ase.Atoms(**d) for d in info]

        #read in the reference data
        with open("SOAP_reference_data.json", "r") as f:
            json_str= f.read()
        self.ref_data = json.loads(json_str)



    def test_SOAP(self):
        for i,d in enumerate(self.ref_data[:]):
            #get dataset and compute desciptors AND gradients
            qs = d["quippy_str"]
            print( i+1, "/", len(self.ref_data), qs)
            dataset = self.datasets[d["dataset_name"]]
            desc =  quippy.descriptors.Descriptor(qs)
            output = desc.calc(dataset, grad=True)

            #check the power spectrum
            perm = np.array(d["perm"])
            X_ref  = np.array(d["X"])
            ps_list = np.array([ps for x in output for ps in x["data"]])
            X = np.array(ps_list)[perm]
            assert X.shape == X_ref.shape
            assert np.allclose(X, X_ref)

            #check the gradients
            grad_data_ref = np.array(d["grad_data"])
            grad_perm = np.array(d["grad_perm"])
            gi0b_ref = np.array(d["grad_index_0based"])
            grad_data = output[0]["grad_data"][grad_perm]
            gi0b = output[0]["grad_index_0based"][grad_perm]

            assert gi0b.shape == gi0b_ref.shape
            assert np.allclose(gi0b, gi0b_ref)
            assert np.shape(grad_data) == np.shape(grad_data_ref)
            assert np.allclose(grad_data, grad_data_ref)



if __name__ == '__main__':
    unittest.main()
