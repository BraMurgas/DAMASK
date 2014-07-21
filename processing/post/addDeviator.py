#!/usr/bin/env python
# -*- coding: UTF-8 no BOM -*-

import os,re,sys,math,string
from collections import defaultdict
from optparse import OptionParser
import damask

scriptID = '$Id$'
scriptName = scriptID.split()[1]

oneThird = 1.0/3.0

def deviator(m):
  sph = oneThird*(m[0]+m[4]+m[8])
  m[0] = m[0] - sph
  m[4] = m[4] - sph
  m[8] = m[8] - sph
  return  m

# --------------------------------------------------------------------
#                                MAIN
# --------------------------------------------------------------------

parser = OptionParser(option_class=damask.extendableOption, usage='%prog options [file[s]]', description = """
Add column(s) containing deviator of requested tensor column(s).

""", version = string.replace(scriptID,'\n','\\n')
)

parser.add_option('-t','--tensor',      dest='tensor', action='extend', type='string', metavar='<string LIST>', \
                                        help='heading of columns containing tensor field values')
parser.add_option('-s','--spherical',   dest='hydrostatic', action='store_true',\
                                        help='also add sperical part of tensor (hydrostatic component, pressure)')
parser.set_defaults(hydrostatic = False)
parser.set_defaults(tensor = [])

(options,filenames) = parser.parse_args()

if len(options.tensor) == 0:
  parser.error('no data column specified...')

datainfo = {                                                                                        # list of requested labels per datatype
             'tensor':     {'len':9,
                            'label':[]},
           }

datainfo['tensor']['label'] += options.tensor

# ------------------------------------------ setup file handles -----------------------------------
files = []
if filenames == []:
  files.append({'name':'STDIN', 'input':sys.stdin, 'output':sys.stdout, 'croak':sys.stderr})
else:
  for name in filenames:
    if os.path.exists(name):
      files.append({'name':name, 'input':open(name), 'output':open(name+'_tmp','w'), 'croak':sys.stderr})

# ------------------------------------------ loop over input files ---------------------------------------  
for file in files:
  if file['name'] != 'STDIN': file['croak'].write('\033[1m'+scriptName+'\033[0m: '+file['name']+'\n')
  else: file['croak'].write('\033[1m'+scriptName+'\033[0m\n')

  table = damask.ASCIItable(file['input'],file['output'],False)                                     # make unbuffered ASCII_table
  table.head_read()                                                                                 # read ASCII header info
  table.info_append(string.replace(scriptID,'\n','\\n') + '\t' + ' '.join(sys.argv[1:]))

  active = defaultdict(list)
  column = defaultdict(dict)

  for datatype,info in datainfo.items():
    for label in info['label']:
      key = {True :'1_%s',
             False:'%s'   }[info['len']>1]%label
      if key not in table.labels:
        file['croak'].write('column %s not found...\n'%key)
      else:
        active[datatype].append(label)
        column[datatype][label] = table.labels.index(key)                                           # remember columns of requested data

# ------------------------------------------ assemble header --------------------------------------- 
  for datatype,labels in active.items():                                                            # loop over vector,tensor
    for label in labels:                                                                            # loop over all requested determinants
      table.labels_append(['%i_dev(%s)'%(i+1,label) for i in xrange(9)])                            # extend ASCII header with new labels
      if(options.hydrostatic): table.labels_append('sph(%s)'%label)
  table.head_write()

# ------------------------------------------ process data ---------------------------------------  
  outputAlive = True
  while outputAlive and table.data_read():                                                          # read next data line of ASCII table
    for datatype,labels in active.items():                                                          # loop over vector,tensor
      for label in labels:                                                                          # loop over all deviators
        myTensor = map(float,table.data[column[datatype][label]:
                             column[datatype][label]+datainfo[datatype]['len']])
        table.data_append(deviator(myTensor))
        if(options.hydrostatic): table.data_append(oneThird*(myTensor[0]+myTensor[4]+myTensor[8]))

    outputAlive = table.data_write()                                                                # output processed line

# ------------------------------------------ output result ---------------------------------------  
  outputAlive and table.output_flush()                                                              # just in case of buffered ASCII table

  file['input'].close()                                                                             # close input ASCII table (works for stdin)
  file['output'].close()                                                                            # close output ASCII table (works for stdout)
  if file['name'] != 'STDIN':
    os.rename(file['name']+'_tmp',file['name'])                                                     # overwrite old one with tmp new
